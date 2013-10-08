package main

import (
	bench "./isucon2013"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"
	"github.com/wsxiaoys/terminal/color"
)

const (
	apiEndpoint                = "https://isucon2013.kayac.com/api/benchmark/"
	infoEndpoint               = "http://169.254.169.254"
	apiKeyFile                 = "/tmp/isucon3.apikey"
	messageAPIError            = "@{r}[ERROR] API呼び出しで予期しないエラーが発生しました. 運営に問い合わせてください."
	messageInvalidAPIKey       = "@{r}[ERROR] 入力されたAPI keyがサーバ上に見つかりません. 管理画面で確認してください"
	messagePleaseRegister      = "@{r}[ERROR] API key 登録が完了していません. --register [apikey] を実行してください"
	messageInvalidInstanceType = "@{r}[ERROR] 実行可能なインスタンスタイプは %s のみです. 現在 %s で実行されています\n"
	messageResultOk            = "@{g}[OK]"
	messageInitFailed          = "@{r}[ERROR] 初期データ投入に失敗しました"
	messageUserInitFailed      = "@{r}[ERROR] ユーザ定義初期化コマンド実行に失敗しました"
	instanceTypeRequired       = "m3.xlarge"
	workloadFactor             = 2
	allowFails                 = 3
	initialDataDir             = "/opt/isucon/data"
	initialDataMD5             = "4381fd6bb578c8a38e4c55f89eca7166  init.sql.gz\n"
	initialLoader              = "/opt/isucon/bin/initialloader"
	userInitTimeout            = "60"
	DEBUG                      = true
)

var (
	apiKey       string
	amiId        string
	instanceId   string
	instanceType string
	cpuInfo      string
	seconds      = 60
	endpoint     = "http://localhost"
)

type APIResponse struct {
	Ok         bool   `json:"ok"`
	Message    string `json:"message"`
	StatusCode int    `json:"statuscode"`
}

type BenchmarkResult struct {
	RawScore float64
	Fails    int
	Score    float64
	Logs     *[]string
}

func getMetaData(key string) string {
	res, err := http.Get(infoEndpoint + "/latest/meta-data/" + key)
	if err != nil {
		log.Printf("meta-data error: %v", err)
		os.Exit(1)
	}
	if res.StatusCode == http.StatusOK {
		data, _ := ioutil.ReadAll(res.Body)
		return string(data)
	}
	log.Printf("meta-data error: %v", err)
	os.Exit(1)
	return ""
}

func loadApiKey() string {
	if DEBUG {
		return "debugapikey"
	}
	apiKeyBytes, err := ioutil.ReadFile(apiKeyFile)
	if err != nil {
		log.Println(err)
		return ""
	}
	return string(apiKeyBytes)
}

func getCpuInfo() string {
	b, err := ioutil.ReadFile("/proc/cpuinfo")
	if err != nil {
		return fmt.Sprintf("%v", err)
	}
	return string(b)
}

func callAPI(path string, values url.Values) *APIResponse {
	if DEBUG {
		return &APIResponse{
			StatusCode: 200,
			Ok:         true,
			Message:    "OK",
		}
	}

	values.Set("ami_id", amiId)
	values.Set("api_key", apiKey)
	values.Set("instance_id", instanceId)
	values.Set("instance_type", instanceType)

	res, err := http.PostForm(apiEndpoint+path, values)
	if err != nil {
		log.Printf("API error: %v", err)
		return &APIResponse{
			StatusCode: 500,
		}
	}
	contentType := res.Header.Get("Content-Type")
	apiRes := &APIResponse{
		StatusCode: res.StatusCode,
	}
	if matched, _ := regexp.MatchString("^application/json", contentType); matched {
		data, _ := ioutil.ReadAll(res.Body)
		if err := json.Unmarshal(data, apiRes); err != nil {
			log.Panicf("API error: %v", err)
		}
	} else {
		apiRes.Ok = false
		apiRes.Message = http.StatusText(res.StatusCode)
	}
	return apiRes
}

func register(newApiKey string) {
	if err := ioutil.WriteFile(apiKeyFile, []byte(newApiKey), 0600); err != nil {
		log.Fatal(err)
		os.Exit(1)
	}
	apiKey = newApiKey
	apiRes := callAPI("register", url.Values{"api_key": {newApiKey}})
	if !apiRes.Ok {
		if apiRes.StatusCode == http.StatusNotFound {
			color.Println(messageInvalidAPIKey)
		} else {
			color.Println(messageAPIError)
			color.Println(apiRes.Message)
		}
		os.Exit(1)
	}
	log.Printf("OK: %s", apiRes.Message)
}

func main() {
	rand.Seed(time.Now().UnixNano())
	runtime.GOMAXPROCS(runtime.NumCPU())
	if DEBUG {
		log.Println("<<<DEBUG build>>>")
		instanceType = "m3.xlarge"
		instanceId = "i-isucondebug"
		amiId = "ami-isucondebug"
		cpuInfo = "dummy"
	} else {
		instanceType = getMetaData("instance-type")
		instanceId = getMetaData("instance-id")
		amiId = getMetaData("ami-id")
		cpuInfo = getCpuInfo()
	}

	if instanceType != instanceTypeRequired {
		color.Printf(messageInvalidInstanceType, instanceTypeRequired, instanceType)
		os.Exit(1)
	}

	var newApiKey *string = flag.String("register", "", "register a new API key")
	flag.Parse()

	if *newApiKey != "" {
		register(*newApiKey)
		os.Exit(0)
	}
	apiKey = loadApiKey()
	if apiKey == "" {
		color.Println(messagePleaseRegister)
		os.Exit(1)
	}

	if len(flag.Args()) == 0 {
		showUsageAndExit()
	}
	command := flag.Args()[0]
	if command == "test" {
		var testWorkload *int = flag.Int("workload", 1, "benchmark workload")
		var testEndpoint *string = flag.String("endpoint", endpoint, "debugging endpoint")
		var testSeconds *int = flag.Int("seconds", 60, "running seconds")
		var accessLog *bool = flag.Bool("accesslog", false, "show access log")
		if DEBUG {
			os.Args = flag.Args()
			flag.Parse()
		}
		workload := *testWorkload
		endpoint = *testEndpoint
		seconds  = *testSeconds
		bench.AccessLog = *accessLog
		log.Println("test mode")
		result := runBenchmark(workload)
		showResult(result)
	} else if command == "benchmark" {
		var workload *int = flag.Int("workload", 1, "benchmark workload")
		var initScript *string = flag.String("init", "", "init script")
		os.Args = flag.Args()
		flag.Parse()
		if *workload < 1 {
			*workload = 1
		}
		log.Println("benchmark mode")
		apiRes := callAPI("start", url.Values{})
		if !apiRes.Ok {
			color.Println(messageAPIError)
			os.Exit(1)
		}
		initializeData(*initScript)

		log.Printf("sleeping %d sec...", 5)
		time.Sleep(time.Duration(5) * time.Second)

		result := runBenchmark(*workload)
		showResult(result)
		if result.Score == 0.0 {
			os.Exit(0)
		}
		if DEBUG {
			os.Exit(0)
		}
		apiRes = callAPI("result", url.Values{
			"score":   {fmt.Sprintf("%.1f", result.Score)},
			"cpuinfo": {cpuInfo},
			"log":     {strings.Join(*result.Logs, "\n")},
		})
		if apiRes.Ok {
			color.Println(messageResultOk)
		} else {
			color.Println(messageAPIError)
			os.Exit(1)
		}
	} else {
		showUsageAndExit()
	}
}

func initializeData(initScript string) {
	log.Printf("initialize data...\n")
	sh := []string{
		"#!/bin/sh",
		"set -e",
		"cd " + initialDataDir,
		"md5sum -c checksum",
		"pigz -dc init.sql.gz | mysql -uisucon isucon",
	}
	defer os.Remove(initialLoader)
	if err := ioutil.WriteFile(initialLoader, []byte(strings.Join(sh, "\n")), 0700); err != nil {
		color.Println(fmt.Sprintf("%s %v", messageInitFailed, err))
		os.Exit(1)
	}
	checksum := initialDataDir + "/checksum";
	defer os.Remove(checksum)
	if err := ioutil.WriteFile(checksum, []byte(initialDataMD5), 0600); err != nil {
		color.Println(fmt.Sprintf("%s %v", messageInitFailed, err))
		os.Exit(1)
	}
	loader := exec.Command(initialLoader)
	if err := loader.Run(); err != nil {
		color.Println(fmt.Sprintf("%s %v", messageInitFailed, err))
		os.Exit(1)
	}
	if initScript == "" {
		return
	}

	log.Printf("run %s timeout %s sec...\n", initScript, userInitTimeout)
	userInit := exec.Command("timeout", userInitTimeout, initScript)
	if err := userInit.Run(); err != nil {
		color.Println(fmt.Sprintf("%s %v", messageUserInitFailed, err))
		os.Exit(1)
	}
	log.Println("done")
}

func runBenchmark(workload int) *BenchmarkResult {
	log.Printf("run benchmark workload: %d\n", workload)

	load := workload + 1
	var allWorkers int
	if workload == 0 {
		allWorkers = 1
	} else {
		allWorkers = load * load * workloadFactor
	}
	staticWorkers := workload
	recentWorkers := workload
	workerId := allWorkers

	// spawn workers
	ch := make(chan *bench.Result)
	for i := 0; i < staticWorkers; i++ {
		workerId--
		go func(id int) {
			client := bench.NewClient(id)
			ch <- client.LoadStatic(endpoint, seconds)
		}(workerId)
	}
	for i := 0; i < recentWorkers; i++ {
		workerId--
		go func(id int) {
			client := bench.NewClient(id)
			ch <- client.CrawlRecent(endpoint, seconds)
		}(workerId)
	}
	for workerId > 0 {
		workerId--
		go func(id int) {
			client := bench.NewClient(id)
			ch <- client.Crawl(endpoint, seconds)
		}(workerId)
	}
	// summerize result
	score := 0.0
	successes := 0
	fails := 0
	logs := make([]string, 0)
	for i := 0; i < allWorkers; i++ {
		result := <-ch // fetch result from crawler
		score += result.Score
		fails += result.Fails
		successes += result.Successes
		for _, l := range *result.Reason {
			logs = append(logs, l)
		}
	}
	xfails := math.Max(float64(fails-allowFails), 0.0) // allowFailsまでは0扱い
	rate := math.Max((100.0 - float64(xfails*xfails)), 0)
	finalScore := score * rate / 100.0
	log.Println("done benchmark")
	return &BenchmarkResult{
		RawScore: score,
		Fails:    fails,
		Score:    finalScore,
		Logs:     &logs,
	}
}

func showUsageAndExit() {
	fmt.Printf("Usage: %s\n", os.Args[0])
	fmt.Println("  test [--workload N]")
	fmt.Println("  benchmark [--workload N] [--init /path/to/script]")
	fmt.Println()
	os.Exit(1)
}

func showResult(r *BenchmarkResult) {
	if r.Score == 0.0 {
		color.Println("@{r}Result:   FAIL")
	} else {
		color.Println("@{g}Result:   SUCCESS")
	}
	fmt.Printf("RawScore: %.1f\n", r.RawScore)
	fmt.Printf("Fails:    %d\n", r.Fails)
	fmt.Printf("Score:    %.1f\n", r.Score)
}
