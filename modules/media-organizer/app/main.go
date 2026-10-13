package main

import (
	"context"
	_ "embed"
	"errors"
	"flag"
	"fmt"
	"html/template"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

//go:embed index.html
var indexHTML string

type server struct {
	qb    *qbit
	media string
	tmpl  *template.Template
}

// item is one finished torrent or one entry under import/.
type item struct {
	ID      string
	Name    string
	Torrent bool
	Root    string
	Files   []string // absolute paths of video files, sorted
}

type fileView struct {
	Rel     string
	Season  string
	Episode string
	Dest    string
}

type itemView struct {
	item
	Kind      string
	Title     string
	Year      string
	Files     []fileView
	MovieFile string
	MovieDest string
	Err       string
}

type op struct{ src, dst string }

func main() {
	listen := flag.String("listen", ":8083", "listen address")
	qbURL := flag.String("qbittorrent", "http://127.0.0.1:8081", "qBittorrent Web UI URL")
	media := flag.String("media", "/var/lib/media", "media root holding import/, movies/ and tv/")
	flag.Parse()

	s := &server{qb: newQbit(*qbURL), media: *media, tmpl: template.Must(template.New("index").Parse(indexHTML))}
	go s.sweepLoop()

	http.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) { s.render(w, r.Context(), "", nil) })
	http.HandleFunc("POST /file", s.file)
	http.HandleFunc("POST /ignore", s.ignore)
	log.Fatal(http.ListenAndServe(*listen, nil))
}

func videosUnder(root string) []string {
	var out []string
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.Type().IsRegular() && isVideo(d.Name()) {
			out = append(out, p)
		}
		return nil
	})
	sort.Strings(out)
	return out
}

func (s *server) items(ctx context.Context) ([]item, error) {
	var items []item
	ts, qerr := s.qb.completed(ctx)
	for _, t := range ts {
		if t.hasTag(tagFiled) || t.hasTag(tagIgnored) {
			continue
		}
		items = append(items, item{ID: t.Hash, Name: t.Name, Torrent: true, Root: t.ContentPath, Files: videosUnder(t.ContentPath)})
	}
	entries, err := os.ReadDir(filepath.Join(s.media, "import"))
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return items, err
	}
	for _, e := range entries {
		root := filepath.Join(s.media, "import", e.Name())
		if files := videosUnder(root); len(files) > 0 {
			items = append(items, item{ID: "import/" + e.Name(), Name: e.Name(), Root: root, Files: files})
		}
	}
	return items, qerr
}

func (s *server) find(ctx context.Context, id string) (item, error) {
	items, err := s.items(ctx)
	for _, it := range items {
		if it.ID == id {
			return it, nil
		}
	}
	if err != nil {
		return item{}, err
	}
	return item{}, fmt.Errorf("%s is no longer waiting", id)
}

// showYear reuses the year of an existing tv/ folder for the same show, so a
// release without a year joins that folder instead of starting a second one.
func (s *server) showYear(title string) string {
	entries, _ := os.ReadDir(filepath.Join(s.media, "tv"))
	for _, e := range entries {
		if r := parseRelease(e.Name()); e.IsDir() && r.Year != "" && strings.EqualFold(r.Title, title) {
			return r.Year
		}
	}
	return ""
}

func largest(files []string) string {
	best, size := "", int64(-1)
	for _, f := range files {
		if fi, err := os.Stat(f); err == nil && fi.Size() > size {
			best, size = f, fi.Size()
		}
	}
	return best
}

func (s *server) defaults(it item) itemView {
	r := parseRelease(it.Name)
	v := itemView{item: it, Kind: "movie", Title: r.Title, Year: r.Year}
	for _, f := range it.Files {
		fr := parseRelease(filepath.Base(f))
		fv := fileView{Rel: s.rel(it, f)}
		if fr.Episode > 0 {
			// Episode files name the show; a season pack's name adds "S01 Pack".
			if v.Kind == "movie" && fr.Title != "" {
				v.Title, v.Year = fr.Title, fr.Year
			}
			v.Kind = "tv"
			fv.Season, fv.Episode = strconv.Itoa(fr.Season), strconv.Itoa(fr.Episode)
		}
		v.Files = append(v.Files, fv)
	}
	if v.Kind == "tv" && v.Year == "" {
		v.Year = s.showYear(v.Title)
	}
	return v
}

func (s *server) rel(it item, f string) string {
	if r, err := filepath.Rel(it.Root, f); err == nil && r != "." {
		return r
	}
	return filepath.Base(f)
}

// plan fills destinations into v and returns the operations to file it.
// An episode row with an empty episode number is skipped.
func (s *server) plan(v *itemView) ([]op, error) {
	var ops []op
	if v.Kind == "movie" {
		src := largest(v.item.Files)
		dst, err := moviePath(v.Title, v.Year, filepath.Ext(src))
		if err != nil {
			return nil, err
		}
		v.MovieFile, v.MovieDest = s.rel(v.item, src), dst
		ops = append(ops, op{src, dst})
	} else {
		for i := range v.Files {
			fv := &v.Files[i]
			if strings.TrimSpace(fv.Episode) == "" {
				fv.Dest = "(skipped)"
				continue
			}
			season, err1 := strconv.Atoi(strings.TrimSpace(fv.Season))
			episode, err2 := strconv.Atoi(strings.TrimSpace(fv.Episode))
			if err := errors.Join(err1, err2); err != nil {
				return nil, fmt.Errorf("%s: %w", fv.Rel, err)
			}
			dst, err := episodePath(v.Title, v.Year, season, episode, filepath.Ext(fv.Rel))
			if err != nil {
				return nil, fmt.Errorf("%s: %w", fv.Rel, err)
			}
			fv.Dest = dst
			ops = append(ops, op{v.item.Files[i], dst})
		}
		if len(ops) == 0 {
			return nil, errors.New("no episodes to file")
		}
	}
	seen := map[string]bool{}
	for _, o := range ops {
		if seen[o.dst] {
			return nil, fmt.Errorf("%s is the destination of two files", o.dst)
		}
		seen[o.dst] = true
		if _, err := os.Lstat(filepath.Join(s.media, o.dst)); err == nil {
			return nil, fmt.Errorf("%s already exists", o.dst)
		}
	}
	return ops, nil
}

// apply hardlinks torrent files, so seeding continues, and moves imports.
func (s *server) apply(ctx context.Context, it item, ops []op) error {
	for _, o := range ops {
		dst := filepath.Join(s.media, o.dst)
		if err := os.MkdirAll(filepath.Dir(dst), 0o2775); err != nil {
			return err
		}
		link := os.Rename
		if it.Torrent {
			link = os.Link
		}
		if err := link(o.src, dst); err != nil {
			return err
		}
	}
	if it.Torrent {
		return s.qb.addTag(ctx, it.ID, tagFiled)
	}
	if len(videosUnder(it.Root)) == 0 {
		return os.RemoveAll(it.Root)
	}
	return nil
}

func (s *server) file(w http.ResponseWriter, r *http.Request) {
	it, err := s.find(r.Context(), r.FormValue("id"))
	if err != nil {
		s.render(w, r.Context(), err.Error(), nil)
		return
	}
	v := s.defaults(it)
	v.Kind, v.Title, v.Year = r.FormValue("kind"), r.FormValue("title"), r.FormValue("year")
	if v.Kind != "movie" && v.Kind != "tv" {
		v.Kind = "movie"
	}
	for i := range v.Files {
		if r.Form.Has(fmt.Sprintf("e%d", i)) {
			v.Files[i].Season, v.Files[i].Episode = r.FormValue(fmt.Sprintf("s%d", i)), r.FormValue(fmt.Sprintf("e%d", i))
		}
	}
	ops, err := s.plan(&v)
	if err == nil && r.FormValue("action") == "file" {
		if err = s.apply(r.Context(), it, ops); err == nil {
			s.render(w, r.Context(), fmt.Sprintf("Filed %s.", it.Name), nil)
			return
		}
	}
	if err != nil {
		v.Err = err.Error()
	}
	s.render(w, r.Context(), "", &v)
}

func (s *server) ignore(w http.ResponseWriter, r *http.Request) {
	msg := "Ignored."
	if it, err := s.find(r.Context(), r.FormValue("id")); err != nil {
		msg = err.Error()
	} else if !it.Torrent {
		msg = "Only torrents can be ignored; delete the import entry instead."
	} else if err := s.qb.addTag(r.Context(), it.ID, tagIgnored); err != nil {
		msg = err.Error()
	}
	s.render(w, r.Context(), msg, nil)
}

func (s *server) render(w http.ResponseWriter, ctx context.Context, msg string, edited *itemView) {
	items, err := s.items(ctx)
	var errMsg string
	if err != nil {
		errMsg = err.Error()
	}
	views := make([]itemView, 0, len(items))
	for _, it := range items {
		if edited != nil && edited.ID == it.ID {
			views = append(views, *edited)
			continue
		}
		v := s.defaults(it)
		if _, err := s.plan(&v); err != nil {
			v.Err = err.Error()
		}
		views = append(views, v)
	}
	if err := s.tmpl.Execute(w, map[string]any{"Msg": msg, "Err": errMsg, "Items": views}); err != nil {
		log.Print(err)
	}
}

// sweepLoop removes torrents that qBittorrent stopped at the share limit,
// with their files, once they are filed; the library keeps its hardlink.
func (s *server) sweepLoop() {
	for ; ; time.Sleep(10 * time.Minute) {
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		ts, err := s.qb.completed(ctx)
		if err != nil {
			log.Printf("sweep: %v", err)
		}
		for _, t := range ts {
			if t.hasTag(tagFiled) && t.State == "stoppedUP" {
				if err := s.qb.deleteWithFiles(ctx, t.Hash); err != nil {
					log.Printf("sweep: %s: %v", t.Name, err)
				} else {
					log.Printf("sweep: removed %s", t.Name)
				}
			}
		}
		cancel()
	}
}
