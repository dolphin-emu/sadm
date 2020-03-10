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
	MakeStaticRedirector(`/fi(/.*)?`, `https://fifoci.dolphin-emu.org/version`),

	// Versions
	MakeStaticRedirector(`/v(\d.*)/?`, `https://dolphin-emu.org/download/dev/master/`),
	MakeStaticRedirector(`/(\d+[.]\d+-\d+)/?`, `https://dolphin-emu.org/download/dev/master/`),

	// Commits.
	MakeStaticRedirector(`/r([0-9a-f]{6,40})/?`, `https://github.com/dolphin-emu/dolphin/commit/`),
	MakeStaticRedirector(`/r([0-9a-f]{6,40})/(\d+)/?`, `https://github.com/dolphin-emu/dolphin/commit/%s#commitcomment-%s`),

	// Pull requests.
	MakeStaticRedirector(`/pr/?(\d+)/?`, `https://github.com/dolphin-emu/dolphin/pull/`),

	// Issues.
	MakeStaticRedirector(`/i(\d+)/?`, `https://bugs.dolphin-emu.org/issues/`),
	MakeStaticRedirector(`/i(\d+)/(\d+)/?`, `https://bugs.dolphin-emu.org/issues/%s#note-%s`),

	// Wiki.
	MakeStaticRedirector(`/([A-Z0-9]{6})/?`, `https://wiki.dolphin-emu.org/dolphin-redirect.php?gameid=`),

	// Google Code compatibility.
	MakeStaticRedirector(`/p/dolphin-emu/issues/list.*`, `https://bugs.dolphin-emu.org/projects/emulator/issues/#`),
	MakeStaticRedirector(`/p/dolphin-emu/issues/detail.*id=(\d+).*`, `https://bugs.dolphin-emu.org/issues/`),
	MakeStaticRedirector(`/p/dolphin-emu/source/browse(/?(?:$|.*/$))`, `https://github.com/dolphin-emu/dolphin/tree/master`),
	MakeStaticRedirector(`/p/dolphin-emu/source/browse(/?.*)`, `https://github.com/dolphin-emu/dolphin/blob/master`),
	MakeStaticRedirector(`/p/dolphin-emu/source/detail.*r=([0-9a-f]{6,40}).*`, `https://github.com/dolphin-emu/dolphin/commit/`),
	MakeStaticRedirector(`/p/dolphin-emu/source/list/?.*`, `https://github.com/dolphin-emu/dolphin/commits/master/#`),
	MakeStaticRedirector(`/p/dolphin-emu/source/?.*`, `https://github.com/dolphin-emu/dolphin/#`),
	MakeStaticRedirector(`/p/dolphin-emu/w/?.*`, `https://github.com/dolphin-emu/dolphin/wiki#`),
	MakeStaticRedirector(`/p/dolphin-emu/wiki/?.*`, `https://github.com/dolphin-emu/dolphin/wiki#`),
	MakeStaticRedirector(`/p/dolphin-emu/?.*`, `https://dolphin-emu.org/#`),
}

func MakeStaticRedirector(pattern string, url string) Redirector {
	re := regexp.MustCompile("(?i)^" + pattern + "$")
	if url[len(url)-1] == '#' {
		url = url[:len(url)-1]
	} else if !strings.Contains(url, "%") {
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
	s, err := ioutil.ReadFile("README.md")
	if err != nil {
		return "No README found. Cannot provide you with documentation ☹"
	}
	return string(s)
}

func Router(w http.ResponseWriter, req *http.Request) {
	for _, r := range redirectors {
		p := req.URL.Path
		if req.URL.RawQuery != "" {
			p += "?" + req.URL.RawQuery
		}
		matches := r.Matcher.FindStringSubmatch(p)
		if matches != nil {
			url, err := r.Handler(matches[1:])
			if err != nil {
				fmt.Fprintf(w, "Error: %v: %v", r.Handler, err)
				return
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
