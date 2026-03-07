# 免费 TTS 接口文档

本文档整理了 Easydict 使用的四个免费 TTS（文本转语音）服务接口的详细使用方法。

---

## 目录

1. [有道 (Youdao) TTS](#1-有道-youdao-tts)
2. [Bing TTS](#2-bing-tts)
3. [Google TTS](#3-google-tts)
4. [百度 (Baidu) TTS](#4-百度-baidu-tts)
5. [对比总结](#5-对比总结)

---

## 1. 有道 (Youdao) TTS

### 接口信息

- **接口地址**: `https://dict.youdao.com/dictvoice`
- **请求方式**: GET
- **是否需要 Token**: ❌ 不需要
- **是否免费**: ✅ 完全免费

### 请求参数

| 参数 | 类型 | 必填 | 说明 | 示例值 |
|------|------|------|------|--------|
| `audio` | string | ✅ | 要朗读的文本（URL 编码） | `hello` |
| `le` | string | ✅ | 语言代码 | `en`（英语）、`zh`（中文）、`fr`（法语） |
| `type` | string | ✅ | 口音类型 | `1`=英式(UK), `2`=美式(US) |

### 语言代码

| 语言 | 代码 |
|------|------|
| 中文 | `zh` |
| 英语 | `en` |
| 法语 | `fr` |
| 德语 | `de` |
| 日语 | `ja` |
| 韩语 | `ko` |
| 俄语 | `ru` |
| 西班牙语 | `es` |

### 使用示例

#### cURL

```bash
# 美式发音
curl -L "https://dict.youdao.com/dictvoice?audio=hello&le=en&type=2" -o hello_us.mp3

# 英式发音
curl -L "https://dict.youdao.com/dictvoice?audio=hello&le=en&type=1" -o hello_uk.mp3

# 中文
curl -L "https://dict.youdao.com/dictvoice?audio=你好&le=zh&type=2" -o hello_zh.mp3
```

#### Swift

```swift
func youdaoTTS(text: String, language: String = "en", accent: String = "us") -> String {
    let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let accentType = accent == "uk" ? "1" : "2"
    return "https://dict.youdao.com/dictvoice?audio=\(encodedText)&le=\(language)&type=\(accentType)"
}

// 使用示例
let audioURL = youdaoTTS(text: "hello", language: "en", accent: "us")
// 结果: https://dict.youdao.com/dictvoice?audio=hello&le=en&type=2
```

#### Python

```python
import urllib.parse

def youdao_tts(text, language='en', accent='us'):
    encoded_text = urllib.parse.quote(text)
    accent_type = '1' if accent == 'uk' else '2'
    return f"https://dict.youdao.com/dictvoice?audio={encoded_text}&le={language}&type={accent_type}"

# 使用示例
url = youdao_tts("hello", language="en", accent="us")
print(url)  # https://dict.youdao.com/dictvoice?audio=hello&le=en&type=2
```

### 限制与注意事项

- **长度限制**: 自动截断至约 600 字符
- **使用限制**: 这是有道词典网站的内部接口，有道可能随时更改或限制访问
- **音频质量**: ⭐⭐⭐ 中等音质

---

## 2. Bing TTS

### 接口信息

- **接口地址**: `https://www.bing.com/tfettts`
- **请求方式**: POST
- **是否需要 Token**: ✅ 需要（需从 Bing 翻译页面获取）
- **是否免费**: ✅ 完全免费
- **技术基础**: Azure AI 语音合成

### 前置步骤：获取 Token

Bing TTS 需要先获取以下参数：

1. 访问 `https://www.bing.com/translator`
2. 从页面 HTML 中提取：
   - `IG` 值
   - `token`
   - `key`
3. 这些值用于后续的 TTS 请求

### 请求参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `ssml` | string | ✅ | SSML 格式的文本 |
| `token` | string | ✅ | 从 Bing 页面提取的 token |
| `key` | string | ✅ | 从 Bing 页面提取的 key |

### SSML 格式

```xml
<speak version="1.0" xml:lang='en-US'>
  <voice name='en-US-JennyNeural'>
    <prosody rate='-10%'>Hello world</prosody>
  </voice>
</speak>
```

### 支持的语音列表

| 语言 | 代码 | 语音名称 |
|------|------|----------|
| 英语(美式) | en-US | `en-US-JennyNeural` |
| 英语(英式) | en-GB | `en-GB-SoniaNeural` |
| 中文(简体) | zh-CN | `zh-CN-XiaoxiaoNeural` |
| 日语 | ja-JP | `ja-JP-NanamiNeural` |
| 韩语 | ko-KR | `ko-KR-SunHiNeural` |
| 法语 | fr-FR | `fr-FR-DeniseNeural` |
| 德语 | de-DE | `de-DE-KatjaNeural` |
| 西班牙语 | es-ES | `es-ES-ElviraNeural` |

### 使用示例

#### Swift

```swift
import Foundation

func generateSSML(text: String, language: String = "en-US", voiceName: String = "en-US-JennyNeural") -> String {
    let escapedText = text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "'", with: "&apos;")
        .replacingOccurrences(of: "\"", with: "&quot;")
    
    return """
    <speak version="1.0" xml:lang='\(language)'>\
    <voice name='\(voiceName)'>\
    <prosody rate='-10%'>\(escapedText)</prosody>
    </voice>
    </speak>
    """
}

func bingTTS(text: String, token: String, key: String) {
    let ssml = generateSSML(text: text)
    let parameters: [String: Any] = [
        "ssml": ssml,
        "token": token,
        "key": key
    ]
    
    // 使用 POST 请求发送到 https://www.bing.com/tfettts
    // 返回的是音频数据 (MP3)
}
```

#### Python

```python
import requests
import re
import html

def get_bing_config():
    """获取 Bing 翻译页面的 token 和 key"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    response = requests.get('https://www.bing.com/translator', headers=headers)
    
    # 从页面中提取 IG 值
    ig_match = re.search(r'IG:"([^"]+)"', response.text)
    ig = ig_match.group(1) if ig_match else None
    
    # 从页面中提取 token 和 key
    # 注意：实际的提取逻辑可能更复杂
    
    return ig, None, None

def generate_ssml(text, language='en-US', voice_name='en-US-JennyNeural'):
    """生成 SSML"""
    escaped_text = html.escape(text)
    return f"""<speak version="1.0" xml:lang='{language}'><voice name='{voice_name}'><prosody rate='-10%'>{escaped_text}</prosody></voice></speak>"""

def bing_tts(text, token, key):
    """调用 Bing TTS"""
    ssml = generate_ssml(text)
    
    url = 'https://www.bing.com/tfettts'
    data = {
        'ssml': ssml,
        'token': token,
        'key': key
    }
    
    response = requests.post(url, data=data)
    if response.headers.get('Content-Type') == 'audio/mpeg':
        return response.content
    return None
```

### 限制与注意事项

- **长度限制**: 
  - 中文最多 2000 字符
  - 英文最多 7000 字符
- **Token 有效期**: 需要定期重新获取
- **音频质量**: ⭐⭐⭐⭐⭐ 神经网络语音，质量最高
- **稳定性**: 由于依赖页面解析，可能因 Bing 更新而失效

---

## 3. Google TTS

### 接口信息

- **接口地址**: `https://translate.google.com/translate_tts`
- **请求方式**: GET
- **是否需要 Token**: ✅ 需要（需计算 TK 签名）
- **是否免费**: ✅ 免费，但有限制

### 请求参数

| 参数 | 类型 | 必填 | 说明 | 示例值 |
|------|------|------|------|--------|
| `q` | string | ✅ | 要朗读的文本（URL 编码） | `hello` |
| `tl` | string | ✅ | 目标语言代码 | `en`（英语）、`zh-CN`（中文） |
| `tk` | string | ✅ | 签名（通过 Google 算法生成） | 动态计算 |
| `ie` | string | ✅ | 编码 | `UTF-8` |
| `client` | string | ✅ | 客户端标识 | `webapp` |
| `total` | int | ✅ | 总段数 | `1` |
| `idx` | int | ✅ | 当前段索引 | `0` |
| `textlen` | int | ✅ | 文本长度 | `5` |
| `prev` | string | ✅ | 上一页 | `input` |

### 语言代码

| 语言 | 代码 |
|------|------|
| 英语 | `en` |
| 中文(简体) | `zh-CN` |
| 中文(繁体) | `zh-TW` |
| 日语 | `ja` |
| 韩语 | `ko` |
| 法语 | `fr` |
| 德语 | `de` |
| 西班牙语 | `es` |
| 俄语 | `ru` |
| 意大利语 | `it` |

### TK 签名算法

Google TTS 需要计算 `tk` 签名，这是通过 Google 翻译页面的 JavaScript 算法生成的。

简化版算法逻辑：

```javascript
// 伪代码，实际算法更复杂
function generateTK(text, TKK) {
    // TKK 从 Google 翻译页面获取
    // 包含时间戳和密钥
    // 使用位运算和字符编码计算签名
}
```

### 使用示例

#### Swift

```swift
import Foundation
import JavaScriptCore

class GoogleTTS {
    private var tkk: String = ""
    private let context = JSContext()
    
    func updateTKK() async throws {
        // 从 Google 翻译页面获取 TKK 值
        let url = URL(string: "https://translate.google.com")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""
        
        // 从 HTML 中提取 TKK
        // 格式: TKK='434531.3697032472'
        if let match = html.range(of: #"TKK='(\d+\.\d+)'"#, options: .regularExpression) {
            let tkkString = String(html[match])
            // 提取数字部分
            self.tkk = extractTKK(from: tkkString)
        }
        
        // 加载签名 JavaScript 函数
        let jsCode = """
        // Google 的签名算法（简化版）
        function tk(a, b) {
            // 实际的算法更复杂
            // 这里只是示例
            return "123456.789012";
        }
        """
        context?.evaluateScript(jsCode)
    }
    
    func generateSign(text: String) -> String {
        let signFunction = context?.objectForKeyedSubscript("tk")
        return signFunction?.call(withArguments: [text, tkk])?.toString() ?? ""
    }
    
    func getTTSURL(text: String, language: String = "en") async -> String {
        try? await updateTKK()
        let sign = generateSign(text: text)
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        return """
        https://translate.google.com/translate_tts?ie=UTF-8&q=\(encodedText)&tl=\(language)&total=1&idx=0&textlen=\(text.count)&tk=\(sign)&client=webapp&prev=input
        """
    }
}
```

#### Python

```python
import requests
import re
import base64

def generate_tk(text, tkk):
    """
    生成 Google TTS 的 TK 签名
    这是简化版，实际算法更复杂
    """
    # 实际的算法涉及位运算和 TKK 的解析
    # 这里仅作示例
    
    # 解析 TKK
    parts = tkk.split('.')
    if len(parts) != 2:
        return None
    
    # 简化版签名生成（实际实现需要完整的算法）
    # 完整的算法可以参考开源实现
    return "123456.789012"

def get_tkk():
    """从 Google 翻译页面获取 TKK"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    response = requests.get('https://translate.google.com', headers=headers)
    
    # 从页面中提取 TKK
    match = re.search(r"TKK='(\d+\.\d+)'", response.text)
    if match:
        return match.group(1)
    return None

def google_tts(text, language='en'):
    """生成 Google TTS URL"""
    tkk = get_tkk()
    if not tkk:
        return None
    
    tk = generate_tk(text, tkk)
    if not tk:
        return None
    
    from urllib.parse import quote
    encoded_text = quote(text)
    
    url = f"https://translate.google.com/translate_tts?ie=UTF-8&q={encoded_text}&tl={language}&total=1&idx=0&textlen={len(text)}&tk={tk}&client=webapp&prev=input"
    return url

# 使用示例
url = google_tts("hello", language="en")
print(url)
```

### 限制与注意事项

- **长度限制**: 文本长度最多 200 字符
- **签名算法**: 需要正确实现 TK 签名算法，否则会返回错误
- **频率限制**: 频繁调用可能被限制
- **音频质量**: ⭐⭐⭐⭐ 音质较好
- **稳定性**: 签名算法可能因 Google 更新而失效

### 完整的 TK 算法参考

完整的 TK 算法比较复杂，可以参考以下开源项目：

- [google-translate-tts](https://github.com/zackradisic/node-google-translate-tts)
- [google-translate-token](https://github.com/matheuss/google-translate-token)

---

## 4. 百度 (Baidu) TTS

### 接口信息

- **接口地址**: `https://fanyi.baidu.com/gettts`
- **请求方式**: GET
- **是否需要 Token**: ❌ 不需要
- **是否免费**: ✅ 完全免费

### 请求参数

| 参数 | 类型 | 必填 | 说明 | 示例值 |
|------|------|------|------|--------|
| `text` | string | ✅ | 要朗读的文本（URL 编码） | `hello` |
| `lan` | string | ✅ | 语言代码 | `en`（英语）、`zh`（中文）、`uk`（英式英语） |
| `spd` | int | ✅ | 语速 | `3`（英文默认）、`5`（中文默认） |
| `source` | string | ✅ | 来源 | `web` |

### 语言代码

| 语言 | 代码 |
|------|------|
| 中文 | `zh` |
| 英语(美式) | `en` |
| 英语(英式) | `uk` |
| 粤语 | `yue` |
| 日语 | `jp` |
| 韩语 | `kor` |
| 法语 | `fra` |
| 德语 | `de` |
| 西班牙语 | `spa` |
| 俄语 | `ru` |
| 泰语 | `th` |
| 阿拉伯语 | `ara` |
| 葡萄牙语 | `pt` |
| 意大利语 | `it` |
| 荷兰语 | `nl` |
| 希腊语 | `el` |

### 使用示例

#### cURL

```bash
# 美式英语
curl -L "https://fanyi.baidu.com/gettts?text=hello&lan=en&spd=3&source=web" -o hello_us.mp3

# 英式英语
curl -L "https://fanyi.baidu.com/gettts?text=hello&lan=uk&spd=3&source=web" -o hello_uk.mp3

# 中文（女声）
curl -L "https://fanyi.baidu.com/gettts?text=你好世界&lan=zh&spd=5&source=web" -o hello_zh.mp3

# 日语
curl -L "https://fanyi.baidu.com/gettts?text=こんにちは&lan=jp&spd=3&source=web" -o hello_ja.mp3
```

#### Swift

```swift
import Foundation

extension String {
    func urlEncoded() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
    
    func trimmingToMaxLength(_ maxLength: Int) -> String {
        if self.count > maxLength {
            return String(self.prefix(maxLength))
        }
        return self
    }
}

func baiduTTS(text: String, language: String = "en", accent: String? = nil) -> String {
    let trimmedText = text.trimmingToMaxLength(1000)
    let encodedText = trimmedText.urlEncoded()
    
    // 处理英式英语的特殊情况
    var langCode = language
    if language == "en" && accent == "uk" {
        langCode = "uk"
    }
    
    // 设置语速：中文默认 5，其他语言默认 3
    let speed = (langCode == "zh") ? 5 : 3
    
    return "https://fanyi.baidu.com/gettts?text=\(encodedText)&lan=\(langCode)&spd=\(speed)&source=web"
}

// 使用示例
let usURL = baiduTTS(text: "hello", language: "en")
let ukURL = baiduTTS(text: "hello", language: "en", accent: "uk")
let zhURL = baiduTTS(text: "你好世界", language: "zh")

print("美式英语: \(usURL)")
print("英式英语: \(ukURL)")
print("中文: \(zhURL)")
```

#### Python

```python
import urllib.parse

def baidu_tts(text, language='en', accent=None):
    """
    生成百度 TTS URL
    
    Args:
        text: 要朗读的文本
        language: 语言代码（如 'en', 'zh', 'jp'）
        accent: 口音（如 'uk' 表示英式英语）
    
    Returns:
        TTS URL 字符串
    """
    # 截断文本（百度限制 1000 字符）
    if len(text) > 1000:
        text = text[:1000]
    
    # URL 编码
    encoded_text = urllib.parse.quote(text)
    
    # 处理英式英语
    lang_code = language
    if language == 'en' and accent == 'uk':
        lang_code = 'uk'
    
    # 设置语速
    speed = 5 if lang_code == 'zh' else 3
    
    return f"https://fanyi.baidu.com/gettts?text={encoded_text}&lan={lang_code}&spd={speed}&source=web"

# 使用示例
print("美式英语:", baidu_tts("hello", language="en"))
print("英式英语:", baidu_tts("hello", language="en", accent="uk"))
print("中文:", baidu_tts("你好世界", language="zh"))
print("日语:", baidu_tts("こんにちは", language="jp"))
```

#### JavaScript

```javascript
function baiduTTS(text, language = 'en', accent = null) {
    // 截断文本
    const trimmedText = text.length > 1000 ? text.substring(0, 1000) : text;
    
    // URL 编码
    const encodedText = encodeURIComponent(trimmedText);
    
    // 处理英式英语
    let langCode = language;
    if (language === 'en' && accent === 'uk') {
        langCode = 'uk';
    }
    
    // 设置语速
    const speed = langCode === 'zh' ? 5 : 3;
    
    return `https://fanyi.baidu.com/gettts?text=${encodedText}&lan=${langCode}&spd=${speed}&source=web`;
}

// 使用示例
console.log("美式英语:", baiduTTS("hello", "en"));
console.log("英式英语:", baiduTTS("hello", "en", "uk"));
console.log("中文:", baiduTTS("你好世界", "zh"));
```

### 限制与注意事项

- **长度限制**: 文本长度最多 1000 字符
- **语速设置**: 
  - 中文推荐 `spd=5`
  - 其他语言推荐 `spd=3`
- **音频质量**: ⭐⭐⭐ 中等音质
- **稳定性**: 百度翻译的内部接口，相对稳定

---

## 5. 对比总结

### 功能对比表

| 特性 | Youdao | Bing | Google | Baidu |
|------|--------|------|--------|-------|
| **需要 Token** | ❌ | ✅ | ✅ | ❌ |
| **完全免费** | ✅ | ✅ | ✅ | ✅ |
| **音质** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **文本限制** | ~600 字符 | 2000-7000 字符 | ~200 字符 | ~1000 字符 |
| **使用难度** | 简单 | 复杂 | 较复杂 | 简单 |
| **稳定性** | 中 | 中 | 中 | 较高 |
| **支持口音** | 美/英 | 多国家 | 多国家 | 美/英 |
| **技术基础** | 内部接口 | Azure AI | 内部接口 | 内部接口 |

### 推荐使用场景

| 场景 | 推荐服务 | 原因 |
|------|---------|------|
| **日常使用** | Youdao / Baidu | 简单、稳定、无需 token |
| **追求音质** | Bing | Azure 神经网络语音，音质最好 |
| **短文本** | Google | 音质好，适合短词短句 |
| **长文本** | Bing | 支持最长 7000 字符 |
| **快速集成** | Youdao / Baidu | API 最简单，一行代码即可 |
| **商业项目** | Bing / Google | 技术文档完善，相对规范 |

### 注意事项

1. **接口稳定性**: 这些都是翻译网站的内部接口，可能随时更改或限制访问
2. **使用限制**: 建议不要高频调用，避免触发反爬虫机制
3. **商业用途**: 如需商业使用，建议购买官方 API 服务
4. **错误处理**: 生产环境应做好错误处理和降级方案

---

## 参考资料

- [Easydict 源码](https://github.com/tisfeng/Easydict)
- [Azure Speech Service 文档](https://learn.microsoft.com/zh-cn/azure/ai-services/speech-service/speech-synthesis-markup-structure)
- [SSML 规范](https://www.w3.org/TR/speech-synthesis/)

---

*最后更新: 2026-03-07*
