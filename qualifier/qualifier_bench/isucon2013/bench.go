package bench

import (
	"crypto/md5"
	"errors"
	"fmt"
	"github.com/moovweb/gokogiri"
	gokogirihtml "github.com/moovweb/gokogiri/html"
	"github.com/wsxiaoys/terminal/color"
	"io"
	"io/ioutil"
	"log"
	"math/rand"
	"net/http"
	cookiejar "net/http/cookiejar"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	UserAgent   = "ISUCON Agent 2013"
	UserScale   = 400
	Timeout     = int64(10000)
	MaxFails    = 5
	SessionName = "isucon_session"
	MaxCheckers = 4
	staticScore = 0.02
	staticSleep = 10
)

var AccessLog = false
var StaticFiles = map[string]string{
	"/css/bootstrap-responsive.min.css": "f889adb0886162aa4ceab5ff6338d888",
	"/css/bootstrap.min.css":            "4082271c7f87b09c7701ffe554e61edd",
	"/js/jquery.min.js":                 "628072e7212db1e8cdacb22b21752cda",
	"/js/bootstrap.min.js":              "d700a93337122b390b90bbfe21e64f71",
}

type Result struct {
	Successes int
	Score     float64
	Reason    *[]string
	Fails     int
}

func (c *Result) Success(n float64) {
	c.Successes++
	c.Score += n
}
func (c *Result) Fail(s string, v ...interface{}) {
	c.Fails++
	if len(v) == 0 {
		*c.Reason = append(*c.Reason, s)
		log.Println("[FAIL] " + s)
	} else {
		msg := fmt.Sprintf(s, v...)
		*c.Reason = append(*c.Reason, msg)
		log.Println("[FAIL] " + msg)
	}
}

func (c *Client) Success(n float64) {
	if c.Running {
		c.Result.Success(n)
	}
}

func (c *Client) Fail(s string, v ...interface{}) {
	if c.Running {
		c.Result.Fail(s, v...)
	}
}

type Client struct {
	Id                 int
	Client             *http.Client
	Transport          *http.Transport
	Result             *Result
	Running            bool
	Username           *string
	SleepAfterRedirect int64
	Token              string
	Endpoint           string
	IsChecker          bool
	TotalMemos         int
}

func NewClient(id int) *Client {
	self := &Client{}
	self.initClient()
	self.Id = id
	self.IsChecker = (id < MaxCheckers)
	debugLog("clientid:%d\tisChecker:%v\n", self.Id, self.IsChecker)
	return self
}

func debugLog(s string, v ...interface{}) {
	if AccessLog {
		log.Println(color.Sprintf("@{kw}" + s, v...))
	}
}

func (c *Client) requestWithTimeout(req *http.Request, f func(r *http.Response, e error)) (resp *http.Response, err error) {
	ch := make(chan bool)
	req.Header.Add("User-Agent", UserAgent)
	debugLog("client:%d\tmethod:%s\turi:%s", c.Id, req.Method, req.URL)
	start := time.Now()
	go func() {
		resp, err = c.Client.Do(req)
		ch <- true
	}()
	timer := time.After(time.Duration(Timeout) * time.Millisecond)
	waiting := true
	for waiting {
		select {
		case <-ch:
			waiting = false
		case <-timer:
			c.Transport.CancelRequest(req)
			err = errors.New(fmt.Sprintf("Timeout %s", req.URL))
			waiting = false
		}
	}
	end := time.Now()
	elapsed := int64(end.Sub(start) / time.Millisecond) // msec
	if err == nil {
		debugLog("client:%d\tmethod:%s\turi:%s\tstatus:%d\treq_time:%v", c.Id, resp.Request.Method, resp.Request.URL, resp.StatusCode, elapsed)
	}

	if f != nil {
		f(resp, err)
	}
	return resp, err
}

func (c *Client) initClient() {
	jar, _ := cookiejar.New(&cookiejar.Options{})
	c.Transport = &http.Transport{}
	c.Client = &http.Client{
		Transport: c.Transport,
		Jar:       jar,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 10 {
				return errors.New("stopped after 10 redirects")
			}
			if c.SleepAfterRedirect > 0 {
				time.Sleep(time.Duration(c.SleepAfterRedirect) * time.Second)
				c.SleepAfterRedirect = 0
			}
			req.Header.Add("User-Agent", UserAgent)
			return nil
		},
	}
	c.SleepAfterRedirect = 0
	reasons := make([]string, 0)
	c.Result = &Result{
		Reason: &reasons,
	}
	c.TotalMemos = 0
}

func (c *Client) Stop() {
	c.Running = false
}

func (c *Client) LoadStatic(endpoint string, seconds int) (result *Result) {
	c.Endpoint = endpoint
	c.Running = true
	time.AfterFunc(time.Duration(seconds)*time.Second, func() { c.Stop() })
	for c.Running && c.Result.Fails < MaxFails {
		for file, _ := range StaticFiles {
			req, _ := http.NewRequest("GET", endpoint+file, nil)
			c.requestWithTimeout(
				req,
				func(resp *http.Response, err error) {
					c.defaultResponseHandler(resp, err, 200, staticScore)
				},
			)
			time.Sleep(time.Duration(staticSleep) * time.Millisecond)
		}
	}
	return c.Result
}

func (c *Client) CrawlRecent(endpoint string, seconds int) (result *Result) {
	c.Endpoint = endpoint
	c.Running = true
	time.AfterFunc(time.Duration(seconds)*time.Second, func() { c.Stop() })
	var page int
	for c.Running && c.Result.Fails < MaxFails {
		if c.TotalMemos / 100 > 0 {
			page = rand.Intn(c.TotalMemos / 100)
		} else {
			page = 1
		}
		path := fmt.Sprintf("/recent/%d", page)
		req, _ := http.NewRequest("GET", endpoint+path, nil)
		c.requestWithTimeout(
			req,
			func(resp *http.Response, err error) {
				c.recentHandler(resp, err)
			},
		)
	}
	return c.Result
}

func (c *Client) Crawl(endpoint string, seconds int) (result *Result) {
	var req *http.Request
	c.Endpoint = endpoint
	c.Running = true
	time.AfterFunc(time.Duration(seconds)*time.Second, func() { c.Stop() })
	for c.Running && c.Result.Fails < MaxFails {
		// 毎回 CookieJarは新しくする
		jar, _ := cookiejar.New(&cookiejar.Options{})
		c.Client.Jar = jar
		c.Token = ""

		// GET /
		req, _ = http.NewRequest("GET", endpoint, nil)
		c.requestWithTimeout(
			req,
			func(resp *http.Response, err error) {
				c.topHandler(resp, err, "")
			},
		)
		for file, md5sum := range StaticFiles {
			req, _ := http.NewRequest("GET", endpoint+file, nil)
			c.requestWithTimeout(
				req,
				func(resp *http.Response, err error) {
					c.md5ResponseHandler(resp, err, 200, md5sum)
				},
			)
		}

		// GET /signin
		req, _ = http.NewRequest("GET", endpoint+"/signin", nil)
		c.requestWithTimeout(req, c.signinHandler)

		// POST /signin
		userid := rand.Intn(UserScale) + 1 // 1 〜 UserScale
		user := fmt.Sprintf("isucon%d", userid)
		req = NewPostRequest(
			endpoint+"/signin",
			url.Values{"username": {user}, "password": {user}},
		)
		c.Username = &user
		c.requestWithTimeout(req, c.mypageHandler)

		endpoint_url, _ := url.Parse(endpoint)
		for _, cookie := range c.Client.Jar.Cookies(endpoint_url) {
			if cookie.Name != SessionName {
				c.Fail("invalid cookie.name=%s", cookie.Name)
			}
		}

		// POST /memo
		c.SleepAfterRedirect = 1
		title := randomWord()
		isprivate := rand.Intn(2)
		req = NewPostRequest(
			endpoint+"/memo",
			url.Values{
				"sid":        {c.Token},
				"content":    {makeMarkdownContent(title)},
				"is_private": {fmt.Sprintf("%d", isprivate)},
			},
		)
		c.requestWithTimeout(
			req,
			func(res *http.Response, err error) {
				c.postMemoHandler(res, err, title, isprivate, c.TotalMemos)
			},
		)
	}
	return c.Result
}

func NewPostRequest(uri string, data url.Values) (req *http.Request) {
	req, _ = http.NewRequest("POST", uri, strings.NewReader(data.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return req
}

func (c *Client) defaultResponseHandler(resp *http.Response, err error, status int, score float64) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp == nil {
		c.Fail("no response")
		return
	}
	_, _ = ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode == status {
		c.Success(score)
	} else {
		c.Fail("status %d != %d %s", resp.StatusCode, status, resp.Request.URL.String())
	}
}

func (c *Client) md5ResponseHandler(resp *http.Response, err error, status int, md5sum string) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp == nil {
		c.Fail("no response")
		return
	}
	if resp.StatusCode == status {
		h := md5.New()
		_, _ = io.Copy(h, resp.Body)
		if !c.IsChecker {
			c.Success(staticScore)
			return
		}
		if md5sum != fmt.Sprintf("%x", h.Sum(nil)) {
			c.Fail("invalid md5 sum")
		}
		resp.Body.Close()
		c.Success(staticScore)
	} else {
		c.Fail(fmt.Sprintf("status %d != %d %s", resp.StatusCode, status, resp.Request.URL.String()))
	}
}

func (c *Client) signoutHandler(resp *http.Response, err error, cb func()) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail(fmt.Sprintf("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String()))
		return
	}
	c.Username = nil
	cb()
}

func (c *Client) signinHandler(resp *http.Response, err error) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	if !c.IsChecker {
		c.Success(1.0)
		return
	}

	doc, docerr := gokogiri.ParseHtml(html)
	defer doc.Free()
	if docerr != nil {
		c.Fail("html parse error")
		return
	}
	nodes, nodeerr := doc.Search("//form//input[@name='username']")
	if nodeerr != nil {
		c.Fail("input element search error")
		return
	}
	if len(nodes) != 1 {
		c.Fail("input element not found")
		return
	}
	c.Success(1.0)
}

func (c *Client) mypageHandler(resp *http.Response, err error) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	if resp.Header.Get("Cache-Control") != "private" {
		c.Fail("invalid Cache-Control header")
		return
	}
	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	doc, docerr := gokogiri.ParseHtml(html)
	defer doc.Free()
	if docerr != nil {
		c.Fail("html parse error")
		return
	}
	nodes, _ := doc.Search("//input[@name='sid' and @type='hidden']")
	if len(nodes) == 0 {
		c.Fail("not found <input type='hidden' name='sid'>")
		return
	}
	c.Token = nodes[0].Attribute("value").String()

	if !c.IsChecker {
		c.Success(1.0)
		return
	}
	c.matchDocNode(doc, "//h2/text()", "Hello\\s+"+*c.Username+"\\!")
	nodes, nodeerr := doc.Search("//div[contains(concat(' ', @class, ' '), ' container ')]/ul/li/a")
	if nodeerr != nil {
		c.Fail("li element search error")
		return
	}
	c.Success(1.0)
	nfetches := rand.Intn(10) + 1
	for i := 0; i < nfetches; i++ {
		node := nodes[ rand.Intn(len(nodes)) ]
		if !c.Running {
			break
		}
		href := node.Attribute("href").String()
		if strings.Index(href, "/") == 0 {
			href = c.Endpoint+href
		}
		req, _ := http.NewRequest("GET", href, nil)
		c.requestWithTimeout(req, c.memoHandler)
	}
}

func (c *Client) memoHandler(resp *http.Response, err error) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	if !c.IsChecker {
		c.Success(1.0)
		return
	}

	xpath := "//h2/text()"
	var str string
	if c.Username != nil {
		str = "Hello\\s+" + *c.Username + "\\!"
	} else {
		str = "Hello\\s+\\!"
	}
	doc := c.matchHtmlNode(html, xpath, str)

	if c.Username != nil {
		c.matchDocNode(doc, "//input[@value='SignOut' and @type='submit']", "SignOut")
	} else {
		c.matchDocNode(doc, "//ul[contains(concat(' ', @class, ' '), ' nav ')]", "SignIn")
	}

	nodes, _ := doc.Search("//link[@href='/']")
	for _, node := range nodes {
		req, _ := http.NewRequest("GET", c.Endpoint+node.Attribute("href").String(), nil)
		c.requestWithTimeout(
			req,
			func(resp *http.Response, err error) {
				c.defaultResponseHandler(resp, err, 200, 0.0)
			},
		)
	}
}

func (c *Client) topHandler(resp *http.Response, err error, matchTitle string) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	if !c.IsChecker {
		c.Success(1.0)
		return
	}

	doc, docerr := gokogiri.ParseHtml(html)
	if docerr != nil {
		c.Fail("html parse error")
		return
	}

	nodes, _ := doc.Search("//p[@id='pager']/span[@id='total']/text()")
	if len(nodes) != 1 {
		c.Fail("no pager")
		return
	}
	c.TotalMemos, _ = strconv.Atoi(nodes[0].String())

	nodes, _ = doc.Search("//ul[@id='memos']//li")
	if len(nodes) != 100 {
		c.Fail("invalid memos list")
		return
	}
	if matchTitle == "" {
		c.Success(1.0)
		return
	}

	for _, node := range nodes {
		matched, _ := regexp.MatchString(matchTitle, node.String())
		if matched {
			c.Success(1.0)
			return
		}
	}

	c.Fail("no match title: %s", matchTitle)
}

func (c *Client) recentHandler(resp *http.Response, err error) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	doc, docerr := gokogiri.ParseHtml(html)
	if docerr != nil {
		c.Fail("html parse error")
		return
	}
	nodes, _ := doc.Search("//ul[@id='memos']//li")
	if len(nodes) == 0 {
		c.Fail("memos too few")
		return
	}
	nodes, _ = doc.Search("//p[@id='pager']/span[@id='total']/text()")
	if len(nodes) != 1 {
		c.Fail("no pager")
		return
	}
	c.TotalMemos, _ = strconv.Atoi(nodes[0].String())
	c.Success(1.0)
}

func (c *Client) postMemoHandler(resp *http.Response, err error, title string, isprivate int, recentTotalMemos int) {
	if err != nil {
		c.Fail(err.Error())
		return
	}
	if resp.StatusCode != 200 {
		c.Fail("status %d != 200 %s", resp.StatusCode, resp.Request.URL.String())
		return
	}
	memoUrl := resp.Request.URL
	if matched, _ := regexp.MatchString("/memo/[0-9]+", memoUrl.String()); !matched {
		c.Fail("invalid post memo URL %s", memoUrl.String())
		return
	}

	html, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	xpath := "//div[contains(concat(' ', @class, ' '), ' container ')]//div[@id='content_html']//h1/text()"
	doc := c.matchHtmlNode(html, xpath, title)

	xpath = "//a[@id='older']"
	nodes, _ := doc.Search(xpath)
	if len(nodes) != 1 {
		c.Fail("element is not found: %s", xpath)
	} else {
		href := nodes[0].Attribute("href").String()
		req, _ := http.NewRequest("GET", href, nil)
		c.requestWithTimeout(req, c.memoHandler)
	}

	xpath = "//p[@id='author']/text()"
	nodes, _ = doc.Search(xpath)
	if len(nodes) != 1 {
		c.Fail("element is not found: %s", xpath)
		return
	}
	var expectedStatus int
	if isprivate == 1 {
		expectedStatus = 404
		matched, _ := regexp.MatchString("Private", nodes[0].String())
		if !matched {
			c.Fail("not private")
		}
	} else {
		expectedStatus = 200
		req, _ := http.NewRequest("GET", c.Endpoint, nil)
		c.requestWithTimeout(
			req,
			func(resp *http.Response, err error) {
				c.topHandler(resp, err, title)
			},
		)
	}
	if c.IsChecker && isprivate == 0 { // checker のみ totalが変わってるか
		path := fmt.Sprintf("/recent/%d", int(c.TotalMemos/100)-1)
		req, _ := http.NewRequest("GET", c.Endpoint+path, nil)
		c.requestWithTimeout(
			req,
			func(resp *http.Response, err error) {
				c.recentHandler(resp, err)
			},
		)
		if recentTotalMemos >= c.TotalMemos {
			c.Fail("total not changed")
		}
	}

	// POST /signout
	signoutReq := NewPostRequest(
		c.Endpoint+"/signout",
		url.Values{"sid": {c.Token}},
	)
	signoutCb := func() {
		cbReq, _ := http.NewRequest("GET", memoUrl.String(), nil)
		c.requestWithTimeout(
			cbReq,
			func(resp *http.Response, err error) {
				c.defaultResponseHandler(resp, err, expectedStatus, 1.0)
			},
		)
		if expectedStatus == 200 {
			c.requestWithTimeout(
				cbReq,
				func(resp *http.Response, err error) {
					c.memoHandler(resp, err)
				},
			)
		}
	}
	c.requestWithTimeout(
		signoutReq,
		func(res *http.Response, err error) {
			c.signoutHandler(res, err, signoutCb)
		},
	)
}

func (c *Client) matchDocNode(doc *gokogirihtml.HtmlDocument, xpath string, str string) *gokogirihtml.HtmlDocument {
	nodes, nodeerr := doc.Search(xpath)
	if nodeerr != nil {
		c.Fail("element search error")
		return doc
	}
	if len(nodes) == 0 {
		c.Fail("element is not found: %s", xpath)
		return doc
	}
	matched, _ := regexp.MatchString(str, nodes[0].String())
	if matched {
		c.Success(1.0)
		return doc
	}
	c.Fail("%s match %s", xpath, str)
	return doc
}

func (c *Client) matchHtmlNode(html []byte, xpath string, str string) *gokogirihtml.HtmlDocument {
	doc, docerr := gokogiri.ParseHtml(html)
	if docerr != nil {
		c.Fail("html parse error")
		return doc
	}
	nodes, nodeerr := doc.Search(xpath)
	if nodeerr != nil {
		c.Fail("element search error")
		return doc
	}
	if len(nodes) == 0 {
		c.Fail("element is not found: %s", xpath)
		return doc
	}
	matched, _ := regexp.MatchString(str, nodes[0].String())
	if matched {
		c.Success(1.0)
		return doc
	}
	c.Fail("%s match %s", xpath, str)
	return doc
}

func makeMarkdownContent(title string) (markdown string) {
	return fmt.Sprintf("# %s\n\n## %s\n\n* %s\n* %s\n* %s\n\n```\n%s```\n",
		title,
		randomWord(), randomWord(), randomWord(), randomWord(),
		randomWord(),
	)
}

func randomWord() (title string) {
	l := len(DictWords)
	word := DictWords[rand.Intn(l)]
	for i := 0; i < rand.Intn(10); i++ {
		word = word + " " + DictWords[rand.Intn(l)]
	}
	return word
}
