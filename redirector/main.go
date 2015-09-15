package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
	"regexp"
	"strings"
)

type RedirectHandler func([]string) (string, error)

type Redirector struct {
	Matcher *regexp.Regexp
	Handler RedirectHandler
}

var redirectors = []Redirector{
	// Random website locations.
	MakeStaticRedirector(`/dl(/.*)?`, `https://dolphin-emu.org/download`),
	MakeStaticRedirector(`/gh(/.*)?`, `https://github.com/dolphin-emu/dolphin`),
	MakeStaticRedirector(`/git(/.*)?`, `https://github.com/dolphin-emu/dolphin`),
	MakeStaticRedirector(`/faq(/.*)?`, `https://dolphin-emu.org/docs/faq`),
	MakeStaticRedirector(`/bbs(/.*)?`, `https://forums.dolphin-emu.org`),
	MakeStaticRedirector(`/pr(/.*)?`, `https://github.com/dolphin-emu/dolphin/pulls`),
	MakeStaticRedirector(`/i(/.*)?`, `https://bugs.dolphin-emu.org/projects/emulator/issues`),

	// Commits.
	MakeStaticRedirector(`/r([0-9a-f]{6,40})/?`, `https://github.com/dolphin-emu/dolphin/commit/`),
	MakeStaticRedirector(`/r([0-9a-f]{6,40})/(\d+)/?`, `https://github.com/dolphin-emu/dolphin/commit/%s#commitcomment-%s`),

	// Pull requests.
	MakeStaticRedirector(`/pr/?(\d+)/?`, `https://github.com/dolphin-emu/dolphin/pull/`),

	// Issues.
	MakeStaticRedirector(`/i(\d+)/?`, `https://bugs.dolphin-emu.org/issues/`),
	MakeStaticRedirector(`/i(\d+)/(\d+)/?`, `https://bugs.dolphin-emu.org/issues/%s#note-%s`),
}

func MakeStaticRedirector(pattern string, url string) Redirector {
	re := regexp.MustCompile("(?i)^" + pattern + "$")
	if !strings.Contains(url, "%") {
		url += "%s"
	}
	return Redirector{
		Matcher: re,
		Handler: func(args []string) (string, error) {
			if len(args) > 0 {
				iargs := make([]interface{}, len(args))
				for i, v := range args {
					iargs[i] = v
				}
				return fmt.Sprintf(url, iargs...), nil
			}
			return url, nil
		},
	}
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
	for _, r := range redirectors {
		matches := r.Matcher.FindStringSubmatch(req.URL.Path)
		if matches != nil {
			url, err := r.Handler(matches[1:])
			if err != nil {
				fmt.Fprintf(w, "Error: %v: %v", r.Handler, err)
				return
			}
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
