/// Provider → available models mapping for the Dual Model editor.
///
/// Selecting a provider updates the model dropdown to show only models
/// supported by that provider.  The sentinel value `'custom...'` in
/// the ollama list triggers a free-text TextField for custom model names.
library;

/// Map from provider name → ordered list of supported model strings.
const Map<String, List<String>> kProviderModels = {
  'google': [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.5-pro',
    'gemini-1.5-pro',
  ],
  'anthropic': [
    'claude-3-5-haiku-20241022',
    'claude-sonnet-4-5',
    'claude-3-5-sonnet-20241022',
    'claude-3-opus-20240229',
  ],
  'openai': [
    'gpt-4o-mini',
    'gpt-4o',
    'gpt-4-turbo',
    'o1-mini',
    'o3-mini',
  ],
  'groq': [
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ],
  'mistral': [
    'mistral-small-latest',
    'mistral-medium-latest',
    'mistral-large-latest',
  ],
  'ollama': [
    'gemma3:1b',
    'gemma3:4b',
    'llama3.2:3b',
    'mistral:7b',
    'phi3:mini',
    'custom...', // sentinel — selecting this shows a free-text TextField
  ],
};

/// Sentinel value that triggers a custom model TextField in the ollama list.
const String kOllamaCustomSentinel = 'custom...';

/// Return the first model for [provider], falling back to an empty string.
String defaultModelForProvider(String provider) {
  final list = kProviderModels[provider];
  return (list != null && list.isNotEmpty) ? list.first : '';
}
