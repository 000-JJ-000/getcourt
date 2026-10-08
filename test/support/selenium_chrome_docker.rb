# Headless Chromium inside Docker needs sandbox flags and must use the
# distro chromedriver/binary. Selenium Manager otherwise downloads a mismatched
# ChromeDriver that fails to start (ECONNREFUSED on 127.0.0.1).
if File.exist?("/.dockerenv") || ENV["CHROME_NO_SANDBOX"] == "1"
  require "selenium-webdriver"

  chromium = ENV["CHROME_BIN"].presence ||
    %w[/usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome].find { |path| File.exist?(path) }
  chromedriver = ENV["CHROMEDRIVER_PATH"].presence ||
    %w[/usr/bin/chromedriver /usr/local/bin/chromedriver].find { |path| File.exist?(path) }

  if chromium && chromedriver
    Selenium::WebDriver::Chrome::Service.driver_path = chromedriver
    chrome_binary = chromium

    Selenium::WebDriver::Chrome::Options.prepend(Module.new do
      define_method(:initialize) do |*args, **kwargs, &block|
        super(*args, **kwargs, &block)
        self.binary = chrome_binary
        add_argument("--headless=new")
        add_argument("--no-sandbox")
        add_argument("--disable-dev-shm-usage")
        add_argument("--disable-gpu")
        add_argument("--window-size=1400,1400")
      end
    end)
  end
end
