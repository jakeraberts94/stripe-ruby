#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple web dashboard for the Stripe Ruby SDK library.
# Serves on port 3000 and runs the test suite, displaying results.

require "webrick"
require "json"
require "fileutils"
require "pathname"

# ── Load gem info ──────────────────────────────────────────────────────────
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "stripe"

GEM_VERSION = Stripe::VERSION
GEM_NAME = "stripe"
GEM_DESCRIPTION = "Ruby bindings for the Stripe API"

# ── Test results (shared between background thread and request handler) ────
TEST_RESULTS = {
  status: "pending",
  output: "",
  summary: "",
  counts: {},
  started_at: nil,
  finished_at: nil,
}
TEST_MUTEX = Mutex.new

# ── Run the test suite in a background thread ───────────────────────────────
Thread.new do
  TEST_MUTEX.synchronize do
    TEST_RESULTS[:status] = "running"
    TEST_RESULTS[:started_at] = Time.now
  end

  # Run the full test suite via rake
  output = `bundle exec rake test 2>&1`

  counts = {}
  # Parse Test::Unit summary line, e.g.:
  # "2100 tests, 2614 assertions, 0 failures, 0 errors, 0 pendings, 0 omissions, 0 notifications"
  if output =~ /(\d+)\s+tests?,\s*(\d+)\s+assertions?,\s*(\d+)\s+failures?,\s*(\d+)\s+errors?,\s*(\d+)\s+pendings?/i
    counts = {
      tests: Regexp.last_match(1).to_i,
      assertions: Regexp.last_match(2).to_i,
      failures: Regexp.last_match(3).to_i,
      errors: Regexp.last_match(4).to_i,
      pendings: Regexp.last_match(5).to_i,
    }
  end

  all_passed = counts[:failures].to_i == 0 && counts[:errors].to_i == 0

  TEST_MUTEX.synchronize do
    TEST_RESULTS[:output] = output
    TEST_RESULTS[:counts] = counts
    TEST_RESULTS[:summary] = if counts.empty?
      "Could not parse test results"
    else
      "#{counts[:tests]} tests, #{counts[:assertions]} assertions, #{counts[:failures]} failures, #{counts[:errors]} errors, #{counts[:pendings]} pendings"
    end
    TEST_RESULTS[:status] = all_passed ? "passed" : "failed"
    TEST_RESULTS[:finished_at] = Time.now
  end
end

# ── HTML generation ────────────────────────────────────────────────────────
def build_html
  results = TEST_MUTEX.synchronize { TEST_RESULTS.dup }
  status = results[:status]

  status_label = {
    "pending" => "Starting…",
    "running" => "Running tests…",
    "passed" => "All tests passed",
    "failed" => "Tests completed (with failures)",
  }.fetch(status, status)

  status_color = {
    "pending" => "#6b7280",
    "running" => "#635bff",
    "passed" => "#00a86b",
    "failed" => "#df1b41",
  }.fetch(status, "#6b7280")

  counts_html = if results[:counts].any?
    <<~HTML
      <div class="stats">
        <div class="stat"><span class="num">#{results[:counts][:tests]}</span><span class="label">Tests</span></div>
        <div class="stat"><span class="num">#{results[:counts][:assertions]}</span><span class="label">Assertions</span></div>
        <div class="stat"><span class="num">#{results[:counts][:failures]}</span><span class="label">Failures</span></div>
        <div class="stat"><span class="num">#{results[:counts][:errors]}</span><span class="label">Errors</span></div>
        <div class="stat"><span class="num">#{results[:counts][:pendings]}</span><span class="label">Pendings</span></div>
      </div>
    HTML
  else
    ""
  end

  output_html = if results[:output] && results[:output].length > 0
    escaped = results[:output]
      .gsub("&", "&amp;")
      .gsub("<", "&lt;")
      .gsub(">", "&gt;")
    # Show last 200 lines to keep page manageable
    lines = escaped.split("\n")
    shown = lines.length > 200 ? lines.last(200) : lines
    <<~HTML
      <div class="output-section">
        <h2>Test Output <span class="muted">(last #{shown.length} lines)</span></h2>
        <pre class="output">#{shown.join("\n")}</pre>
      </div>
    HTML
  else
    ""
  end

  duration = if results[:started_at] && results[:finished_at]
    "%.1f seconds" % (results[:finished_at] - results[:started_at])
  elsif results[:started_at]
    "in progress…"
  else
    ""
  end

  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Stripe Ruby SDK — Test Dashboard</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          background: #0a0e27;
          color: #e6e6e6;
          min-height: 100vh;
          padding: 2rem;
        }
        .container { max-width: 900px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 2.5rem; }
        .logo {
          font-size: 2.5rem;
          font-weight: 700;
          letter-spacing: -0.03em;
          margin-bottom: 0.5rem;
        }
        .logo span { color: #635bff; }
        .subtitle { color: #9ca3af; font-size: 1.1rem; }
        .badge {
          display: inline-block;
          background: #1a1f3a;
          border: 1px solid #2a3050;
          border-radius: 999px;
          padding: 0.25rem 0.75rem;
          font-size: 0.85rem;
          color: #9ca3af;
          margin-top: 0.75rem;
        }
        .status-card {
          background: #12162e;
          border: 1px solid #2a3050;
          border-radius: 16px;
          padding: 2rem;
          margin-bottom: 1.5rem;
        }
        .status-row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          flex-wrap: wrap;
          gap: 1rem;
        }
        .status-badge {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          background: #{status_color}22;
          color: #{status_color};
          border: 1px solid #{status_color}55;
          border-radius: 999px;
          padding: 0.5rem 1.25rem;
          font-weight: 600;
          font-size: 1rem;
        }
        .status-badge .dot {
          width: 8px; height: 8px;
          border-radius: 50%;
          background: #{status_color};
          #{status == "running" ? "animation: pulse 1s ease-in-out infinite;" : ""}
        }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
        .duration { color: #9ca3af; font-size: 0.95rem; }
        .summary { color: #d1d5db; margin-top: 1rem; font-size: 1rem; }
        .stats {
          display: flex;
          gap: 1rem;
          margin-top: 1.5rem;
          flex-wrap: wrap;
        }
        .stat {
          background: #0a0e27;
          border: 1px solid #2a3050;
          border-radius: 12px;
          padding: 1rem 1.5rem;
          text-align: center;
          flex: 1;
          min-width: 100px;
        }
        .stat .num {
          display: block;
          font-size: 1.75rem;
          font-weight: 700;
          color: #fff;
        }
        .stat .label {
          display: block;
          font-size: 0.8rem;
          color: #9ca3af;
          margin-top: 0.25rem;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .output-section {
          background: #12162e;
          border: 1px solid #2a3050;
          border-radius: 16px;
          padding: 1.5rem;
          margin-bottom: 1.5rem;
        }
        .output-section h2 {
          font-size: 1.1rem;
          margin-bottom: 1rem;
          color: #d1d5db;
        }
        .muted { color: #6b7280; font-weight: 400; font-size: 0.85rem; }
        pre.output {
          background: #0a0e27;
          border-radius: 8px;
          padding: 1rem;
          font-family: "SF Mono", Monaco, "Cascadia Code", "Courier New", monospace;
          font-size: 0.82rem;
          line-height: 1.5;
          overflow-x: auto;
          max-height: 500px;
          overflow-y: auto;
          white-space: pre-wrap;
          color: #c8c8c8;
        }
        .info-section {
          background: #12162e;
          border: 1px solid #2a3050;
          border-radius: 16px;
          padding: 1.5rem;
          margin-bottom: 1.5rem;
        }
        .info-section h2 { font-size: 1.1rem; margin-bottom: 1rem; color: #d1d5db; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }
        .info-item { display: flex; gap: 0.5rem; }
        .info-item .key { color: #9ca3af; min-width: 120px; }
        .info-item .val { color: #e6e6e6; }
        footer { text-align: center; color: #6b7280; font-size: 0.85rem; margin-top: 2rem; }
        @media (max-width: 600px) {
          .info-grid { grid-template-columns: 1fr; }
          .stat { min-width: 80px; padding: 0.75rem; }
          .stat .num { font-size: 1.4rem; }
        }
      </style>
      <script>
        if (#{status == "running" || status == "pending"}) {
          setTimeout(() => location.reload(), 5000);
        }
      </script>
    </head>
    <body>
      <div class="container">
        <header>
          <div class="logo">Stripe<span> Ruby</span> SDK</div>
          <div class="subtitle">#{GEM_DESCRIPTION}</div>
          <div class="badge">v#{GEM_VERSION}</div>
        </header>

        <div class="status-card">
          <div class="status-row">
            <div class="status-badge">
              <span class="dot"></span>
              #{status_label}
            </div>
            <div class="duration">#{duration}</div>
          </div>
          #{results[:summary] && results[:summary].length > 0 ? "<div class='summary'>#{results[:summary]}</div>" : ""}
          #{counts_html}
        </div>

        <div class="info-section">
          <h2>Library Info</h2>
          <div class="info-grid">
            <div class="info-item"><span class="key">Gem</span><span class="val">#{GEM_NAME}</span></div>
            <div class="info-item"><span class="key">Version</span><span class="val">#{GEM_VERSION}</span></div>
            <div class="info-item"><span class="key">Ruby required</span><span class="val">&gt;= 3.0.0</span></div>
            <div class="info-item"><span class="key">License</span><span class="val">MIT</span></div>
          </div>
        </div>

        #{output_html}

        <footer>Stripe Ruby SDK — Test Dashboard &middot; Powered by Base44</footer>
      </div>
    </body>
    </html>
  HTML
end

# ── WEBrick server ─────────────────────────────────────────────────────────
server = WEBrick::HTTPServer.new(
  Port: 3000,
  BindAddress: "0.0.0.0",
  AccessLog: [],
  Logger: WEBrick::Log.new("/dev/null"),
)

server.mount_proc "/" do |req, res|
  res["Content-Type"] = "text/html; charset=utf-8"
  res.body = build_html
end

server.mount_proc "/health" do |req, res|
  res["Content-Type"] = "application/json"
  res.body = '{"status":"ok"}'
end

trap("INT") { server.shutdown }
trap("TERM") { server.shutdown }
server.start
