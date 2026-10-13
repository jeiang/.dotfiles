package main

import "testing"

func TestParseRelease(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want release
	}{
		{"Code.3.2025.1080p.WEBRip.10Bit.DDP5.1.x265-NeoNoir.mkv", release{Title: "Code 3", Year: "2025"}},
		{"X-Men.First.Class.2011.PROPER.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.5.1-FGT.mkv", release{Title: "X-Men First Class", Year: "2011"}},
		{"The Prodigy (2009) [xa0scu2].mp4", release{Title: "The Prodigy", Year: "2009"}},
		{"Lanterns.2026.S01E08.1080p.WEB.h264-ETHEL[EZTVx.to].mkv", release{Title: "Lanterns", Year: "2026", Season: 1, Episode: 8}},
		{"Lanterns.S01E07.1080p.HEVC.x265-MeGusta[EZTVx.to].mkv", release{Title: "Lanterns", Season: 1, Episode: 7}},
		{"Show.S02E03.Recap.of.1999.720p.mkv", release{Title: "Show", Season: 2, Episode: 3}},
		{"[Group] Some Show S1E12.mkv", release{Title: "Some Show", Season: 1, Episode: 12}},
		{"2001.A.Space.Odyssey.1968.mkv", release{Title: "2001 A Space Odyssey", Year: "1968"}},
	} {
		if got := parseRelease(tc.in); got != tc.want {
			t.Errorf("parseRelease(%q) = %+v, want %+v", tc.in, got, tc.want)
		}
	}
}

func TestPaths(t *testing.T) {
	got, err := moviePath("Heart Eyes", "2025", ".MKV")
	if want := "movies/Heart Eyes (2025)/Heart Eyes (2025).mkv"; err != nil || got != want {
		t.Errorf("moviePath = %q, %v; want %q", got, err, want)
	}
	got, err = episodePath("Lanterns", "2026", 1, 8, ".mkv")
	if want := "tv/Lanterns (2026)/Season 01/Lanterns (2026) - S01E08.mkv"; err != nil || got != want {
		t.Errorf("episodePath = %q, %v; want %q", got, err, want)
	}
	got, err = moviePath("Mission: Impossible / Part 1", "", ".mp4")
	if want := "movies/Mission - Impossible Part 1/Mission - Impossible Part 1.mp4"; err != nil || got != want {
		t.Errorf("moviePath = %q, %v; want %q", got, err, want)
	}
	for _, bad := range []func() (string, error){
		func() (string, error) { return moviePath(" .. ", "", ".mkv") },
		func() (string, error) { return moviePath("X", "20x5", ".mkv") },
		func() (string, error) { return episodePath("X", "", 1, 0, ".mkv") },
	} {
		if p, err := bad(); err == nil {
			t.Errorf("accepted %q", p)
		}
	}
}
