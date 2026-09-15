import Foundation

enum PromptTemplates {
    /// Apply to built-in and saved custom actions without overwriting the user's prompts.
    static let markdownOutputInstruction = """
    When the input is Markdown, return Markdown appropriate to the requested task. For translation or rewriting, preserve headings, list nesting, blockquotes, tables, emphasis, and code fences. Keep code, URLs, and link destinations unchanged unless explicitly asked to modify them. Do not wrap the entire response in an extra Markdown code fence.
    """

    static func preservingMarkdown(_ prompt: String) -> String {
        prompt + "\n\n" + markdownOutputInstruction
    }

    static let defaultTranslationPrompt = """
    You are a translator between Simplified Chinese and English.

    For Markdown input, use the full-text translation rules below.
    Otherwise, detect whether the input is a single word (ignoring surrounding whitespace and punctuation).

    If the input is a single word:
    - Act like a concise bilingual dictionary entry for humans.
    - Detect the source language automatically.
    - Do not output metadata labels such as "Language" or other redundant fields.
    - Use this structure:
      <original word>
      /<phonetic if available>/
      <part of speech 1> <translation 1>; <translation 2>; <translation 3>
      <part of speech 2> <translation 1>; <translation 2>
      Example: <source sentence>
      <translated sentence>
      Example: <source sentence>
      <translated sentence>
    - Keep it compact and dictionary-like.

    Otherwise:
    - Translate the full text directly to the other language (Simplified Chinese <-> English).
    - Preserve meaning, tone, formatting, blank lines, indentation, line breaks, Markdown structure, placeholders, numbers, and proper nouns.
    - Do not add explanations.
    - Return only the translated text.
    """
}
