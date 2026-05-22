import sys
import os
import httpx
import logging

sys.path.append(os.getcwd())
from app.extractors.tiktok import TikTokExtractor

logging.basicConfig(level=logging.INFO)

def test_specific_short_url():
    url = "https://www.tiktok.com/t/ZTk5b5HCA/"
    extractor = TikTokExtractor()
    
    print(f"Testing resolution for: {url}")
    video_id = extractor._resolve_video_id(url)
    print(f"Extracted Video ID: {video_id}")
    
    if video_id:
        try:
            result = extractor.resolve(url)
            print("Successfully resolved!")
            print(f"Title: {result.title}")
            print(f"Media Type: {result.media_type}")
            print(f"Best URL: {result.best_url}")
            if result.image_urls:
                print(f"Image Count: {len(result.image_urls)}")
        except Exception as e:
            print(f"Resolve step failed: {e}")
    else:
        print("Failed to extract Video ID. Let's try to see where it redirects...")
        with httpx.Client(follow_redirects=True, timeout=10) as client:
            resp = client.get(url, headers=extractor.default_http_headers(extractor._default_referer))
            print(f"Final URL: {resp.url}")
            print(f"Status Code: {resp.status_code}")

if __name__ == "__main__":
    test_specific_short_url()
