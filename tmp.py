import pathlib
text = pathlib.Path('lib/providers/v2ray_provider.dart').read_text(encoding='utf-8')
idx = text.index("_setError('Smart mode connection")
snippet = text[idx-30:idx+120]
print(snippet.encode('unicode_escape').decode())
