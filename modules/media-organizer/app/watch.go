package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	eztvAPI      = "https://eztvx.to/api/get-torrents"
	pollInterval = 30 * time.Minute
	seenTTL      = 90 * 24 * time.Hour
)

var imdbRe = regexp.MustCompile(`^(?:tt)?(\d{7,9})$`)

// rule notifies once for each EZTV release of one show whose title matches
// Pattern. A new rule's first poll only records what already exists.
type rule struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	IMDb    string `json:"imdb"`
	Pattern string `json:"pattern"`
	Primed  bool   `json:"primed"`
}

type watchState struct {
	Rules []rule           `json:"rules"`
	Seen  map[string]int64 `json:"seen"` // torrent hash -> unix time first seen
}

type watcher struct {
	path       string
	ntfyURL    string
	ntfyTopic  string
	ntfyToken  string
	publicURL  string
	client     *http.Client
	poke       chan struct{}
	mu         sync.Mutex
	st         watchState
	lastCheck  time.Time
	lastErrors []string
}

type eztvTorrent struct {
	Hash      string `json:"hash"`
	Title     string `json:"title"`
	MagnetURL string `json:"magnet_url"`
	SizeBytes string `json:"size_bytes"`
}

func newWatcher(path, ntfyURL, topic, tokenFile, publicURL string) (*watcher, error) {
	token, err := os.ReadFile(tokenFile)
	if err != nil {
		return nil, err
	}
	w := &watcher{
		path: path, ntfyURL: strings.TrimRight(ntfyURL, "/"), ntfyTopic: topic,
		ntfyToken: strings.TrimSpace(string(token)), publicURL: strings.TrimRight(publicURL, "/"),
		client: &http.Client{Timeout: 30 * time.Second}, poke: make(chan struct{}, 1),
		st: watchState{Seen: map[string]int64{}},
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return w, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, &w.st); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if w.st.Seen == nil {
		w.st.Seen = map[string]int64{}
	}
	return w, nil
}

// save writes the state atomically; the caller holds mu.
func (w *watcher) save() error {
	data, err := json.MarshalIndent(w.st, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(w.path), ".state-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), w.path)
}

func (w *watcher) addRule(name, imdb, pattern string) error {
	name = strings.TrimSpace(name)
	m := imdbRe.FindStringSubmatch(strings.TrimSpace(imdb))
	switch {
	case name == "":
		return errors.New("name is empty")
	case m == nil:
		return fmt.Errorf("IMDb ID %q is not tt followed by 7 to 9 digits", imdb)
	}
	if _, err := regexp.Compile(pattern); err != nil || pattern == "" {
		return fmt.Errorf("pattern %q: %v", pattern, err)
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	w.st.Rules = append(w.st.Rules, rule{ID: strconv.FormatInt(time.Now().UnixNano(), 36), Name: name, IMDb: m[1], Pattern: pattern})
	if err := w.save(); err != nil {
		return err
	}
	select {
	case w.poke <- struct{}{}:
	default:
	}
	return nil
}

func (w *watcher) deleteRule(id string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	for i, r := range w.st.Rules {
		if r.ID == id {
			w.st.Rules = append(w.st.Rules[:i], w.st.Rules[i+1:]...)
			return w.save()
		}
	}
	return fmt.Errorf("rule %s does not exist", id)
}

type watchView struct {
	Rules     []rule
	LastCheck time.Time
	Errors    []string
}

func (w *watcher) view() watchView {
	w.mu.Lock()
	defer w.mu.Unlock()
	return watchView{Rules: append([]rule(nil), w.st.Rules...), LastCheck: w.lastCheck, Errors: w.lastErrors}
}

func (w *watcher) loop() {
	t := time.NewTicker(pollInterval)
	for {
		w.poll()
		select {
		case <-t.C:
		case <-w.poke:
		}
	}
}

func (w *watcher) fetch(ctx context.Context, imdb string) ([]eztvTorrent, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, eztvAPI+"?"+url.Values{"imdb_id": {imdb}, "limit": {"100"}}.Encode(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := w.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("EZTV: %s", resp.Status)
	}
	var body struct {
		Torrents []eztvTorrent `json:"torrents"`
	}
	return body.Torrents, json.NewDecoder(resp.Body).Decode(&body)
}

func (w *watcher) poll() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	rules := w.view().Rules
	var errs []string
	now := time.Now()
	for _, r := range rules {
		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", r.Name, err))
			continue
		}
		ts, err := w.fetch(ctx, r.IMDb)
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", r.Name, err))
			continue
		}
		for _, t := range ts {
			w.mu.Lock()
			_, seen := w.st.Seen[t.Hash]
			w.mu.Unlock()
			if seen || !re.MatchString(t.Title) {
				continue
			}
			if r.Primed {
				if err := w.notify(ctx, r, t); err != nil {
					errs = append(errs, fmt.Sprintf("%s: ntfy: %v", r.Name, err))
					continue // retry on the next poll
				}
			}
			w.mu.Lock()
			w.st.Seen[t.Hash] = now.Unix()
			w.mu.Unlock()
		}
		w.mu.Lock()
		for i := range w.st.Rules {
			if w.st.Rules[i].ID == r.ID {
				w.st.Rules[i].Primed = true
			}
		}
		w.mu.Unlock()
	}
	w.mu.Lock()
	for h, at := range w.st.Seen {
		if now.Sub(time.Unix(at, 0)) > seenTTL {
			delete(w.st.Seen, h)
		}
	}
	if err := w.save(); err != nil {
		errs = append(errs, "save: "+err.Error())
	}
	w.lastCheck, w.lastErrors = now, errs
	w.mu.Unlock()
	for _, e := range errs {
		log.Printf("watch: %s", e)
	}
}

func (w *watcher) notify(ctx context.Context, r rule, t eztvTorrent) error {
	msg := t.Title
	if n, err := strconv.ParseFloat(t.SizeBytes, 64); err == nil && n > 0 {
		msg += fmt.Sprintf(" (%.1f GB)", n/1e9)
	}
	payload, err := json.Marshal(map[string]any{
		"topic":   w.ntfyTopic,
		"title":   r.Name,
		"message": msg,
		"actions": []map[string]any{{
			"action": "http",
			"label":  "Add to qBittorrent",
			"url":    w.publicURL + "/add",
			"method": "POST",
			"body":   t.MagnetURL,
			"clear":  true,
		}},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.ntfyURL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+w.ntfyToken)
	resp, err := w.client.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return errors.New(resp.Status)
	}
	return nil
}
