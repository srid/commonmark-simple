
## 0.2.1.0

- Add `flattenNestedLinks` and apply it inside `parseMarkdown` /
  `parseMarkdownWithFrontMatter`. The autolink extension in `commonmark-hs`
  emits nested `Link` nodes whenever a URL or email address appears inside a
  parent link's label, which Pandoc renders as multiple split hyperlinks
  ([emanote#349](https://github.com/srid/emanote/issues/349)). The new pass
  unwraps the inner `Link` while preserving its label content, leaving a
  single hyperlink as written.

## 0.2.0.0

- Require newer version of `commonmark-*` libraries support the [alerts extension](https://github.com/jgm/commonmark-hs/pull/135)

## 0.1.0.0

- Initial release
