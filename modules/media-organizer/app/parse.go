package main

import (
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var (
	episodeRe  = regexp.MustCompile(`(?i)\bS(\d{1,2}) ?E(\d{1,3})`)
	yearRe     = regexp.MustCompile(`\b(19\d{2}|20\d{2})\b`)
	leadTagRe  = regexp.MustCompile(`^\s*\[[^\]]*\]\s*`)
	sampleRe   = regexp.MustCompile(`(?i)\bsample\b`)
	unsafeName = strings.NewReplacer("/", "", `\`, "", ":", " -", "*", "", "?", "", `"`, "", "<", "", ">", "", "|", "")
)

var videoExts = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true, ".ts": true, ".wmv": true,
}

func isVideo(name string) bool {
	return videoExts[strings.ToLower(filepath.Ext(name))] && !sampleRe.MatchString(name)
}

type release struct {
	Title   string
	Year    string
	Season  int
	Episode int
}

// parseRelease reads a scene-style or "Title (Year)" name; the title is
// everything before the year or episode marker.
func parseRelease(name string) release {
	if videoExts[strings.ToLower(filepath.Ext(name))] {
		name = strings.TrimSuffix(name, filepath.Ext(name))
	}
	name = leadTagRe.ReplaceAllString(name, "")
	name = strings.NewReplacer(".", " ", "_", " ").Replace(name)

	var r release
	cut := len(name)
	if m := episodeRe.FindStringSubmatchIndex(name); m != nil {
		r.Season, _ = strconv.Atoi(name[m[2]:m[3]])
		r.Episode, _ = strconv.Atoi(name[m[4]:m[5]])
		cut = m[0]
	}
	// The last year before the episode marker; a leading number is the title
	// (2001 A Space Odyssey) and a later one is part of the episode title.
	for _, m := range yearRe.FindAllStringSubmatchIndex(name[:cut], -1) {
		if m[0] > 0 {
			r.Year, cut = name[m[2]:m[3]], m[0]
		}
	}
	r.Title = strings.Trim(name[:cut], " -([")
	return r
}

func cleanComponent(s string) (string, error) {
	s = strings.Trim(strings.Join(strings.Fields(unsafeName.Replace(s)), " "), " .")
	if s == "" {
		return "", errors.New("title is empty")
	}
	return s, nil
}

func named(title, year string) (string, error) {
	title, err := cleanComponent(title)
	if err != nil {
		return "", err
	}
	year = strings.TrimSpace(year)
	if year == "" {
		return title, nil
	}
	if !yearRe.MatchString(year) || len(year) != 4 {
		return "", fmt.Errorf("year %q is not a year", year)
	}
	return fmt.Sprintf("%s (%s)", title, year), nil
}

// moviePath is relative to the media root: movies/Title (Year)/Title (Year).ext.
func moviePath(title, year, ext string) (string, error) {
	n, err := named(title, year)
	if err != nil {
		return "", err
	}
	return filepath.Join("movies", n, n+strings.ToLower(ext)), nil
}

// episodePath is relative to the media root:
// tv/Show (Year)/Season NN/Show (Year) - SNNEMM.ext.
func episodePath(show, year string, season, episode int, ext string) (string, error) {
	n, err := named(show, year)
	if err != nil {
		return "", err
	}
	if season < 0 || episode < 1 {
		return "", fmt.Errorf("season %d episode %d is not an episode", season, episode)
	}
	return filepath.Join("tv", n, fmt.Sprintf("Season %02d", season),
		fmt.Sprintf("%s - S%02dE%02d%s", n, season, episode, strings.ToLower(ext))), nil
}
