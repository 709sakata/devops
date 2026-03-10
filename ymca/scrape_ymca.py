import urllib.request
import urllib.parse
import json
import re
import time

URL = "https://www.ymcajapan.org/about/local/"

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as res:
        return res.read().decode("utf-8")

def geocode(address):
    query = urllib.parse.quote(address)
    url = f"https://msearch.gsi.go.jp/address-search/AddressSearch?q={query}"
    req = urllib.request.Request(url, headers={"User-Agent": "ymca-scraper/1.0"})
    with urllib.request.urlopen(req) as res:
        data = json.loads(res.read())
        if data:
            lng, lat = data[0]["geometry"]["coordinates"]
            return lat, lng
    return None, None

html = fetch(URL)

pattern = r'<h2[^>]*>(.*?YMCA.*?)</h2>.*?<dt>(〒?\d{3}-\d{4})</dt>\s*<dd>(.*?)</dd>'
matches = re.findall(pattern, html, re.DOTALL)

results = []
for name, postal, address in matches:
    name = re.sub(r'<.*?>', '', name).strip()
    address = re.sub(r'<.*?>', '', address).strip()
    full_address = f"{postal} {address}"
    lat, lng = geocode(full_address)
    print(f"📍 {name}: {lat}, {lng}")
    results.append({
        "name": name,
        "postal": postal,
        "address": address,
        "lat": lat,
        "lng": lng
    })
    time.sleep(0.5)

with open("/Users/naokisakata/scripts/ymca/ymca_locations.json", "w") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print(f"\n✅ {len(results)}件保存完了")
