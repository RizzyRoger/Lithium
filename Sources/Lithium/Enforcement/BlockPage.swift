import Foundation

/// The HTML for the block page. Self-contained so the page renders with no
/// network access at all.
enum BlockPage {
    static func html(domain: String, reason: BlockReason, used: TimeInterval, limit: TimeInterval?) -> String {
        let safeDomain = escape(domain)
        let detail: String
        switch reason {
        case .limitReached:
            let spent = SiteRule.format(seconds: used)
            if let limit {
                detail = "You have used your full \(escape(SiteRule.format(seconds: limit))) of \(safeDomain) today (\(escape(spent)))."
            } else {
                detail = "You have used \(escape(spent)) of \(safeDomain) today."
            }
        case .banned:
            detail = "\(safeDomain) is banned for the whole day."
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Site Blocked for the day</title>
        <style>
          :root { color-scheme: dark light; }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: radial-gradient(120% 120% at 50% 0%, #1b2230 0%, #0c0f16 60%);
            color: #e7ecf5;
            font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            padding: 32px;
          }
          .card {
            width: 100%;
            max-width: 560px;
            text-align: center;
            background: rgba(255,255,255,0.045);
            border: 1px solid rgba(255,255,255,0.09);
            border-radius: 22px;
            padding: 52px 44px;
            box-shadow: 0 30px 80px rgba(0,0,0,0.45);
          }
          .mark {
            width: 62px; height: 62px;
            margin: 0 auto 26px;
            border-radius: 50%;
            display: grid; place-items: center;
            background: rgba(255, 92, 92, 0.14);
            border: 1px solid rgba(255, 92, 92, 0.35);
            font-size: 28px;
          }
          h1 {
            margin: 0 0 14px;
            font-size: 29px;
            letter-spacing: -0.4px;
            font-weight: 650;
          }
          .domain {
            display: inline-block;
            margin: 0 0 20px;
            padding: 5px 13px;
            border-radius: 999px;
            background: rgba(255,255,255,0.07);
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 14px;
            color: #b9c6da;
          }
          p { margin: 0 0 10px; color: #9fadc2; font-size: 15px; }
          .reset { margin-top: 26px; font-size: 13px; color: #75849b; }
          .brand {
            margin-top: 32px;
            font-size: 12px;
            letter-spacing: 1.6px;
            text-transform: uppercase;
            color: #56637a;
          }
          @media (prefers-color-scheme: light) {
            body { background: radial-gradient(120% 120% at 50% 0%, #f4f6fb 0%, #e6eaf2 60%); color: #1b2233; }
            .card { background: #fff; border-color: rgba(0,0,0,0.07); box-shadow: 0 24px 60px rgba(20,30,60,0.12); }
            .domain { background: rgba(0,0,0,0.05); color: #4a5568; }
            p { color: #5c6a80; }
          }
        </style>
        </head>
        <body>
          <main class="card">
            <div class="mark">&#9203;</div>
            <h1>Site Blocked for the day</h1>
            <div class="domain">\(safeDomain)</div>
            <p>\(detail)</p>
            <p class="reset" id="reset"></p>
            <div class="brand">Lithium</div>
          </main>
          <script>
            (function () {
              var el = document.getElementById("reset");
              function tick() {
                var now = new Date();
                var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0, 0);
                var ms = midnight - now;
                var h = Math.floor(ms / 3600000);
                var m = Math.floor((ms % 3600000) / 60000);
                el.textContent = "Access returns at midnight, in " + h + "h " + m + "m.";
              }
              tick();
              setInterval(tick, 30000);
            })();
          </script>
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
