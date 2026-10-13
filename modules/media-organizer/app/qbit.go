package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	tagFiled   = "filed"
	tagIgnored = "ignored"
)

// qbit talks to the Web UI API; the localhost whitelist makes login unnecessary.
type qbit struct {
	base   string
	client *http.Client
}

type torrent struct {
	Hash        string `json:"hash"`
	Name        string `json:"name"`
	ContentPath string `json:"content_path"`
	Tags        string `json:"tags"`
	State       string `json:"state"`
}

func (t torrent) hasTag(tag string) bool {
	for _, x := range strings.Split(t.Tags, ",") {
		if strings.TrimSpace(x) == tag {
			return true
		}
	}
	return false
}

func newQbit(base string) *qbit {
	return &qbit{base: strings.TrimRight(base, "/"), client: &http.Client{Timeout: 10 * time.Second}}
}

func (q *qbit) completed(ctx context.Context) ([]torrent, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, q.base+"/api/v2/torrents/info?filter=completed", nil)
	if err != nil {
		return nil, err
	}
	resp, err := q.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qBittorrent: torrents/info: %s", resp.Status)
	}
	var ts []torrent
	return ts, json.NewDecoder(resp.Body).Decode(&ts)
}

func (q *qbit) post(ctx context.Context, path string, form url.Values) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, q.base+"/api/v2/"+path, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := q.client.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("qBittorrent: %s: %s", path, resp.Status)
	}
	return nil
}

func (q *qbit) addTag(ctx context.Context, hash, tag string) error {
	return q.post(ctx, "torrents/addTags", url.Values{"hashes": {hash}, "tags": {tag}})
}

func (q *qbit) deleteWithFiles(ctx context.Context, hash string) error {
	return q.post(ctx, "torrents/delete", url.Values{"hashes": {hash}, "deleteFiles": {"true"}})
}
