#!/bin/bash

echo "=== Testing TTS APIs ==="
echo ""

# Test Youdao TTS (should work)
echo "1. Testing Youdao TTS..."
curl -s -L "https://dict.youdao.com/dictvoice?audio=hello&le=en&type=2" -o /tmp/test_youdao.mp3 -w "Status: %{http_code}, Size: %{size_download} bytes\n"
file /tmp/test_youdao.mp3

# Test Baidu TTS (should work)
echo ""
echo "2. Testing Baidu TTS..."
curl -s -L "https://fanyi.baidu.com/gettts?text=hello&lan=en&spd=3&source=web" -o /tmp/test_baidu.mp3 -w "Status: %{http_code}, Size: %{size_download} bytes\n"
file /tmp/test_baidu.mp3

# Test Google TTS (may not work without token)
echo ""
echo "3. Testing Google TTS (old API - expected to fail)..."
curl -s -L "https://translate.google.com/translate_tts?ie=UTF-8&q=hello&tl=en&total=1&idx=0&textlen=5&client=tw-ob&prev=input" -o /tmp/test_google.mp3 -w "Status: %{http_code}, Size: %{size_download} bytes\n"
file /tmp/test_google.mp3

echo ""
echo "=== Tests complete ==="
ls -lh /tmp/test_*.mp3 2>/dev/null || echo "No test files created"