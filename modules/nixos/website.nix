{
  flake.nixosModules.website = _: {
    services.caddy.virtualHosts.main = rec {
      hostName = "jeiang.dev";
      logFormat = null;
      serverAliases = ["aidanpinard.co" "pinard.co.tt"];
      extraConfig = ''
        import logging ${hostName}
        import compression
        import security_headers
        header Content-Type text/html
        respond <<HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>Under Maintenance</title>
              <style>
                body, html {
                  margin: 0;
                  padding: 0;
                  height: 100%;
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                }
                body {
                  display: flex;
                  justify-content: center;
                  align-items: center;
                  background-color: #f7f9fc;
                  color: #333;
                  text-align: center;
                }
                .maintenance-container {
                  max-width: 600px;
                  padding: 2rem;
                }
                .gear {
                  font-size: 4rem;
                  color: #a0b3c6;
                  margin-bottom: 1rem;
                  animation: spin 8s linear infinite;
                }
                @keyframes spin {
                  from { transform: rotate(0deg); }
                  to { transform: rotate(360deg); }
                }
                h1 {
                  font-size: 2.5rem;
                  margin-bottom: 1rem;
                  color: #2c3e50;
                }
                p {
                  font-size: 1.1rem;
                  line-height: 1.6;
                  color: #5a6c7d;
                }
              </style>
            </head>
            <body>
              <div class="maintenance-container">
                <div class="gear">⚙️</div>
                <h1>Under Maintenance!</h1>
                <p>
                  I'm currently redoing my website and doing some server maintenance, so this will be all that you see
                  until I get around to finishing it.
                </p>
              </div>
            </body>
          </html>
          HTML 200
      '';
    };
  };
}
