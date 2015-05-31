package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"regexp"
)

type RawRedirect struct {
	ShortUrl       string   // format string for local URLs
	LongUrl        string   // format string for where to redirect
	PatternParams  []string // format arguments to turn ShortUrl/LongUrl into a valid pattern for Regexp.MustCompile()
	TemplateParams []string // format arguments to turn ShortUrl/LongUrl into a valid template for Regexp.ExpandString()
}

type Redirect struct {
	ShortRegex    *regexp.Regexp
	LongRegex     *regexp.Regexp
	ShortTemplate string
	LongTemplate  string
}

var redirects = []Redirect{
	Compile(RawRedirect{"/r%s/%s", "https://github.com/dolphin-emu/dolphin/commit/%s#commitcomment-%s", []string{`([0-9a-fA-F]{6,40})`, `(\d+)`}, []string{"$1", "$2"}}),
	Compile(RawRedirect{"/r%s", "https://github.com/dolphin-emu/dolphin/commit/%s", []string{`([0-9a-fA-F]{6,40})`}, []string{"$1"}}),
	Compile(RawRedirect{"/i%s%s", "https://code.google.com/p/dolphin-emu/issues/detail?id=%s%s", []string{`(\d+)`, `/?`}, []string{"$1", ""}}),
	Compile(RawRedirect{"/i%s/%s", "https://code.google.com/p/dolphin-emu/issues/detail?id=$1#c$2", []string{`(\d+)`, `(\d+)`}, []string{"$1", "$2"}}),
	Compile(RawRedirect{"/pr%s%s", "https://github.com/dolphin-emu/dolphin/pull/%[2]s%[1]s", []string{`/?`, `(\d+)`}, []string{"", "$1"}}),
	Compile(RawRedirect{"/pr%s", "https://github.com/dolphin-emu/dolphin/pulls%s", []string{`(/.*)?`}, []string{"$1"}}),
	Compile(RawRedirect{"/dl%s", "https://dolphin-emu.org/download%s", []string{`(/.*)?`}, []string{"$1"}}),
	Compile(RawRedirect{"/gh%s", "https://github.com/dolphin-emu/dolphin%s", []string{`(/.*)?`}, []string{"$1"}}),
	Compile(RawRedirect{"/git%s", "https://github.com/dolphin-emu/dolphin%s", []string{`(/.*)?`}, []string{"$1"}}),
	Compile(RawRedirect{"/faq%s", "https://dolphin-emu.org/docs/faq%s", []string{`(/.*)?`}, []string{"$1"}}),
	Compile(RawRedirect{"/bbs%s", "https://forums.dolphin-emu.org%s", []string{`(/.*)?`}, []string{"$1"}}),
}

func Compile(rr RawRedirect) Redirect {
	var r Redirect
	r.ShortRegex = regexp.MustCompile(fmt.Sprintf("^%s$", FillParams(rr.ShortUrl, rr.PatternParams)))
	r.LongRegex = regexp.MustCompile(fmt.Sprintf("^%s$", FillParams(rr.LongUrl, rr.PatternParams)))
	r.ShortTemplate = FillParams(rr.ShortUrl, rr.TemplateParams)
	r.LongTemplate = FillParams(rr.LongUrl, rr.TemplateParams)
	return r
}

func FillParams(format string, params []string) string {
	p := make([]interface{}, len(params))
	for i, v := range params {
		p[i] = v
	}
	return fmt.Sprintf(format, p...)
}

func HandleShorten(w *http.ResponseWriter, req *http.Request) {
	var msg struct {
		LongUrl string `json:"longUrl"`
	}
	if json.NewDecoder(req.Body).Decode(&msg) != nil {
		http.Error(*w, "Could not decode JSON.", 400)
		return
	}

	for _, redirect := range redirects {
		if matches := redirect.LongRegex.FindStringSubmatchIndex(msg.LongUrl); matches != nil {
			var result struct {
				ShortUrl string `json:"id"`
			}
			result.ShortUrl = string(redirect.LongRegex.ExpandString(nil, redirect.ShortTemplate, msg.LongUrl, matches))
			json.NewEncoder(*w).Encode(result)
			return
		}
	}
	http.Error(*w, "Could not shorten URL.", 400)
}

var readmeContents = GetReadme()

func GetReadme() string {
	s, err := ioutil.ReadFile("README")
	if err != nil {
		return "No README found. Cannot provide you with documentation ☹"
	}
	return string(s)
}

func Router(w http.ResponseWriter, req *http.Request) {
	if req.Method == "POST" {
		HandleShorten(&w, req)
		return
	}

	for _, r := range redirects {
		matches := r.ShortRegex.FindStringSubmatchIndex(req.URL.Path)
		if matches != nil {
			url := string(r.ShortRegex.ExpandString(nil, r.LongTemplate, req.URL.Path, matches))
			if req.URL.RawQuery != "" {
				url += "?" + req.URL.RawQuery
			}
			http.Redirect(w, req, url, 302)
			return
		}
	}

	fmt.Fprintf(w, readmeContents)
}

func main() {
	http.HandleFunc("/", Router)
	http.ListenAndServe(":8033", nil)
}
