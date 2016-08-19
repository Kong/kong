-- List taken from https://github.com/ua-parser/uap-core/blob/master/regexes.yaml

return {
  bots = {
    [[(Pingdom.com_bot_version_)(\d+)\.(\d+)]], -- Pingdom
    [[(facebookexternalhit)/(\d+)\.(\d+)]], -- Facebook
    [[Google.*/\+/web/snippet]], -- Google Plus
    [[(Twitterbot)/(\d+)\.(\d+)]], -- Twitter
    [[/((?:Ant-)?Nutch|[A-z]+[Bb]ot|[A-z]+[Ss]pider|Axtaris|fetchurl|Isara|ShopSalad|Tailsweep)[ \-](\d+)(?:\.(\d+)(?:\.(\d+))?)?]], -- Bots Pattern '/name-0.0'
    [[(008|Altresium|Argus|BaiduMobaider|BoardReader|DNSGroup|DataparkSearch|EDI|Goodzer|Grub|INGRID|Infohelfer|LinkedInBot|LOOQ|Nutch|PathDefender|Peew|PostPost|Steeler|Twitterbot|VSE|WebCrunch|WebZIP|Y!J-BR[A-Z]|YahooSeeker|envolk|sproose|wminer)/(\d+)(?:\.(\d+)(?:\.(\d+))?)?]], --Bots Pattern 'name/0.0'
    [[(MSIE) (\d+)\.(\d+)([a-z]\d?)?;.* MSIECrawler]], --MSIECrawler
    [[(Google-HTTP-Java-Client|Apache-HttpClient|http%20client|Python-urllib|HttpMonitor|TLSProber|WinHTTP|JNLP)(?:[ /](\d+)(?:\.(\d+)(?:\.(\d+))?)?)?]], -- Downloader ...
    [[(1470\.net crawler|50\.nu|8bo Crawler Bot|Aboundex|Accoona-[A-z]+-Agent|AdsBot-Google(?:-[a-z]+)?|altavista|AppEngine-Google|archive.*?\.org_bot|archiver|Ask Jeeves|[Bb]ai[Dd]u[Ss]pider(?:-[A-Za-z]+)*|bingbot|BingPreview|blitzbot|BlogBridge|BoardReader(?: [A-Za-z]+)*|boitho.com-dc|BotSeer|\b\w*favicon\w*\b|\bYeti(?:-[a-z]+)?|Catchpoint bot|[Cc]harlotte|Checklinks|clumboot|Comodo HTTP\(S\) Crawler|Comodo-Webinspector-Crawler|ConveraCrawler|CRAWL-E|CrawlConvera|Daumoa(?:-feedfetcher)?|Feed Seeker Bot|findlinks|Flamingo_SearchEngine|FollowSite Bot|furlbot|Genieo|gigabot|GomezAgent|gonzo1|(?:[a-zA-Z]+-)?Googlebot(?:-[a-zA-Z]+)?|Google SketchUp|grub-client|gsa-crawler|heritrix|HiddenMarket|holmes|HooWWWer|htdig|ia_archiver|ICC-Crawler|Icarus6j|ichiro(?:/mobile)?|IconSurf|IlTrovatore(?:-Setaccio)?|InfuzApp|Innovazion Crawler|InternetArchive|IP2[a-z]+Bot|jbot\b|KaloogaBot|Kraken|Kurzor|larbin|LEIA|LesnikBot|Linguee Bot|LinkAider|LinkedInBot|Lite Bot|Llaut|lycos|Mail\.RU_Bot|masidani_bot|Mediapartners-Google|Microsoft .*? Bot|mogimogi|mozDex|MJ12bot|msnbot(?:-media *)?|msrbot|netresearch|Netvibes|NewsGator[^/]*|^NING|Nutch[^/]*|Nymesis|ObjectsSearch|Orbiter|OOZBOT|PagePeeker|PagesInventory|PaxleFramework|Peeplo Screenshot Bot|PlantyNet_WebRobot|Pompos|Read%20Later|Reaper|RedCarpet|Retreiver|Riddler|Rival IQ|scooter|Scrapy|Scrubby|searchsight|seekbot|semanticdiscovery|Simpy|SimplePie|SEOstats|SimpleRSS|SiteCon|Slurp|snappy|Speedy Spider|Squrl Java|TheUsefulbot|ThumbShotsBot|Thumbshots\.ru|TwitterBot|URL2PNG|Vagabondo|VoilaBot|^vortex|Votay bot|^voyager|WASALive.Bot|Web-sniffer|WebThumb|WeSEE:[A-z]+|WhatWeb|WIRE|WordPress|Wotbox|www\.almaden\.ibm\.com|Xenu(?:.s)? Link Sleuth|Xerka [A-z]+Bot|yacy(?:bot)?|Yahoo[a-z]*Seeker|Yahoo! Slurp|Yandex\w+|YodaoBot(?:-[A-z]+)?|YottaaMonitor|Yowedo|^Zao|^Zao-Crawler|ZeBot_www\.ze\.bz|ZooShot|ZyBorg)(?:[ /]v?(\d+)(?:\.(\d+)(?:\.(\d+))?)?)?]], -- Bots
    [[(?:\/[A-Za-z0-9\.]+)? *([A-Za-z0-9 \-_\!\[\]:]*(?:[Aa]rchiver|[Ii]ndexer|[Ss]craper|[Bb]ot|[Ss]pider|[Cc]rawl[a-z]*))/(\d+)(?:\.(\d+)(?:\.(\d+))?)?]], -- Bots General matcher 'name/0.0'
    [[(?:\/[A-Za-z0-9\.]+)? *([A-Za-z0-9 _\!\[\]:]*(?:[Aa]rchiver|[Ii]ndexer|[Ss]craper|[Bb]ot|[Ss]pider|[Cc]rawl[a-z]*)) (\d+)(?:\.(\d+)(?:\.(\d+))?)?]], -- Bots General matcher 'name 0.0'
    [[((?:[A-z0-9]+|[A-z\-]+ ?)?(?: the )?(?:[Ss][Pp][Ii][Dd][Ee][Rr]|[Ss]crape|[A-Za-z0-9-]*(?:[^C][^Uu])[Bb]ot|[Cc][Rr][Aa][Ww][Ll])[A-z0-9]*)(?:(?:[ /]| v)(\d+)(?:\.(\d+)(?:\.(\d+))?)?)?]] -- Bots containing spider|scrape|bot(but not CUBOT)|Crawl
  }
}
