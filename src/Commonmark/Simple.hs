{- | A simple interface to the `commonmark` package for parsing real-world Markdown

Where 'real-world' means the kind of syntax used in the likes of Obsidian Markdown.
-}
module Commonmark.Simple (
    parseMarkdownWithFrontMatter,
    parseMarkdown,
    fullMarkdownSpec,
    flattenNestedLinks,
)
where

import Commonmark qualified as CM
import Commonmark.Extensions qualified as CE
import Commonmark.Pandoc qualified as CP
import Control.Monad.Combinators (manyTill)
import Data.Aeson (FromJSON)
import Data.Yaml qualified as Y
import Text.Megaparsec qualified as M
import Text.Megaparsec.Char qualified as M
import Text.Pandoc.Builder qualified as B
import Text.Pandoc.Definition (Inline (..), Pandoc (..))
import Text.Pandoc.Walk qualified as W

-- | Like `parseMarkdown` but also parses the YAML frontmatter
parseMarkdownWithFrontMatter ::
    forall meta m il bl.
    ( FromJSON meta
    , m ~ Either CM.ParseError
    , bl ~ CP.Cm () B.Blocks
    , il ~ CP.Cm () B.Inlines
    ) =>
    CM.SyntaxSpec m il bl ->
    -- | Path to file associated with this Markdown
    FilePath ->
    -- | Markdown text to parse
    Text ->
    Either Text (Maybe meta, Pandoc)
parseMarkdownWithFrontMatter spec fn s = do
    (mMeta, markdown) <- partitionMarkdown fn s
    mMetaVal <- first show $ (Y.decodeEither' . encodeUtf8) `traverse` mMeta
    blocks <- first show $ join $ CM.commonmarkWith @(Either CM.ParseError) spec fn markdown
    let doc = Pandoc mempty $ B.toList . CP.unCm @() @B.Blocks $ blocks
    pure (mMetaVal, flattenNestedLinks doc)

-- | Parse a Markdown file using commonmark-hs with all extensions enabled
parseMarkdown :: FilePath -> Text -> Either Text Pandoc
parseMarkdown fn s = do
    cmBlocks <- first show $ join $ CM.commonmarkWith @(Either CM.ParseError) fullMarkdownSpec fn s
    let blocks = B.toList . CP.unCm @() @B.Blocks $ cmBlocks
    pure $ flattenNestedLinks $ Pandoc mempty blocks

{- | Replace nested @Link@ nodes inside any @Link@'s label with the inner label
content, dropping the inner link's target.

The @autolink@ extension in @commonmark-hs@ greedily turns bare URLs and email
addresses into autolinks even when they appear inside another link's label.
Once translated to Pandoc, this surfaces as a nested @Link@ — for example,
@[https:\/\/x.com](https:\/\/x.com#a)@ becomes
@Link [Link [Str "https:\/\/x.com"] (...)] (..., "https:\/\/x.com#a")@,
which Pandoc renderers split into two separate hyperlinks.

Flattening normalizes the AST so the inner label survives but the inner link
target is discarded — a single hyperlink, as the author wrote. @Image@ children
are left intact (an image inside a link is a clickable image, not a parser
artifact).

See <https:\/\/github.com\/srid\/emanote\/issues\/349>.
-}
flattenNestedLinks :: (W.Walkable Inline a) => a -> a
flattenNestedLinks = W.walk $ \case
    Link attr inlines target -> Link attr (concatMap unwrap inlines) target
    x -> x
  where
    unwrap (Link _ inner _) = inner
    unwrap x = [x]

type SyntaxSpec' m il bl =
    ( Monad m
    , CM.IsBlock il bl
    , CM.IsInline il
    , Typeable m
    , Typeable il
    , Typeable bl
    , CE.HasEmoji il
    , CE.HasStrikethrough il
    , CE.HasPipeTable il bl
    , CE.HasTaskList il bl
    , CM.ToPlainText il
    , CE.HasFootnote il bl
    , CE.HasMath il
    , CE.HasDefinitionList il bl
    , CE.HasDiv bl
    , CE.HasQuoted il
    , CE.HasSpan il
    , CE.HasAlerts il bl
    )

-- | GFM + official commonmark extensions
fullMarkdownSpec ::
    (SyntaxSpec' m il bl) =>
    CM.SyntaxSpec m il bl
fullMarkdownSpec =
    mconcat
        [ CE.gfmExtensions
        , CE.fancyListSpec
        , CE.footnoteSpec
        , CE.mathSpec
        , CE.smartPunctuationSpec
        , CE.definitionListSpec
        , CE.attributesSpec
        , CE.rawAttributeSpec
        , CE.fencedDivSpec
        , CE.bracketedSpanSpec
        , CE.autolinkSpec
        , CM.defaultSyntaxSpec
        , -- as the commonmark documentation states, pipeTableSpec should be placed after
          -- fancyListSpec and defaultSyntaxSpec to avoid bad results when parsing
          -- non-table lines
          CE.pipeTableSpec
        ]

{- | Identify metadata block at the top, and split it from markdown body.

FIXME: https://github.com/srid/neuron/issues/175
-}
partitionMarkdown :: FilePath -> Text -> Either Text (Maybe Text, Text)
partitionMarkdown =
    parse (M.try splitP <|> fmap (Nothing,) M.takeRest)
  where
    separatorP :: M.Parsec Void Text ()
    separatorP =
        void $ M.string "---" <* M.eol
    splitP :: M.Parsec Void Text (Maybe Text, Text)
    splitP = do
        separatorP
        a <- toText <$> manyTill M.anySingle (M.try $ M.eol *> separatorP)
        b <- M.takeRest
        pure (Just a, b)
    parse :: M.Parsec Void Text a -> String -> Text -> Either Text a
    parse p fn s =
        first (toText . M.errorBundlePretty) $
            M.parse (p <* M.eof) fn s
