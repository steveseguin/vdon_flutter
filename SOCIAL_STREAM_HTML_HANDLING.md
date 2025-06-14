# Social Stream HTML Handling

## Implementation Summary

Chat messages from Social Stream can contain HTML content. We now properly handle this by:

1. **Stripping HTML tags** from all messages
2. **Skipping empty messages** after HTML stripping
3. **Preserving text content** while removing formatting

## HTML Stripping Features

The `_stripHtml` function handles:

### 1. HTML Entity Decoding
- `&nbsp;` → space
- `&amp;` → &
- `&lt;` → <
- `&gt;` → >
- `&quot;` → "
- `&#39;` → '
- `&apos;` → '

### 2. Complete Removal of Script/Style Tags
- Removes `<script>` tags and their content
- Removes `<style>` tags and their content
- Prevents any code execution

### 3. Line Break Handling
- `<br>` tags → newlines
- `<p>` and `<div>` tags → newlines
- Preserves text structure

### 4. Tag Removal
- Strips all remaining HTML tags
- Keeps only text content

### 5. Whitespace Cleanup
- Trims excess whitespace
- Collapses multiple spaces
- Removes empty lines

## Example Transformations

### Input:
```html
<p>Hello <b>world</b>!</p><br>This is a <a href="#">test</a> message.
```

### Output:
```
Hello world!
This is a test message.
```

### Input with image only:
```html
<img src="https://example.com/image.png">
```

### Output:
```
(empty string - message skipped)
```

## Empty Message Handling

Messages are skipped if:
1. They contain only HTML tags with no text
2. They're empty after HTML stripping
3. They only contain whitespace

This prevents showing:
- Image-only messages
- Empty formatting tags
- Messages with only links/media

## Special Cases

### Donations
If a message is empty but has a donation:
- The donation text is used as the message
- Prefixed with 💰 emoji
- Example: "💰 3 hearts"

### Plain Text
Messages without HTML tags pass through unchanged.

## Testing

To test HTML handling:

1. **Send HTML message**:
   ```
   <b>Bold</b> and <i>italic</i> text
   ```
   Result: "Bold and italic text"

2. **Send image-only message**:
   ```
   <img src="test.png">
   ```
   Result: Message skipped

3. **Send complex HTML**:
   ```
   <div><p>Paragraph 1</p><p>Paragraph 2</p></div>
   ```
   Result: "Paragraph 1\nParagraph 2"

4. **Send script/style**:
   ```
   <script>alert('test')</script>Normal text
   ```
   Result: "Normal text"

## Future Enhancement Options

If HTML rendering is desired instead of stripping:

1. Use `flutter_html` package to render HTML
2. Support specific tags (bold, italic, links)
3. Show images/media in chat
4. Custom emoji rendering

For now, stripping provides a clean, safe text-only experience.