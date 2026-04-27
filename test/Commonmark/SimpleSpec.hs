module Commonmark.SimpleSpec where

import Commonmark.Simple (parseMarkdown)
import Test.Hspec
import Text.Pandoc.Definition (Inline (..), Pandoc)
import Text.Pandoc.Walk qualified as W

spec :: Spec
spec = do
    describe "flattenNestedLinks (via parseMarkdown)" $ do
        it "URL label becomes the parent link's text, not a separate autolink" $
            links "[https://www.website.com](https://www.website.com#something)"
                `shouldBe` [("https://www.website.com#something", "https://www.website.com")]
        it "mailto label is preserved as the parent link's text" $
            links "[nobody@example.com](mailto:nobody@example.com?subject=Some%20subject)"
                `shouldBe` [("mailto:nobody@example.com?subject=Some%20subject", "nobody@example.com")]
        it "URLs embedded in a sentence label collapse into one link" $
            links "[A website similar to https://www.foo.com and https://www.bar.com](https://www.baz.com)"
                `shouldBe` [("https://www.baz.com", "A website similar to https://www.foo.com and https://www.bar.com")]
        it "leaves a normal link alone" $
            links "[Emanote](https://github.com/srid/emanote)"
                `shouldBe` [("https://github.com/srid/emanote", "Emanote")]
        it "leaves a bare autolink alone (it is not nested)" $
            links "<https://www.example.com>"
                `shouldBe` [("https://www.example.com", "https://www.example.com")]

-- | Every @Link@ in the document, paired with its target URL and the plain
-- text of its label.
links :: Text -> [(Text, Text)]
links = either error collect . parseMarkdown "<test>"
  where
    collect :: Pandoc -> [(Text, Text)]
    collect = W.query $ \case
        Link _ inlines (url, _) -> [(url, plain inlines)]
        _ -> []

plain :: [Inline] -> Text
plain = W.query $ \case
    Str t -> t
    Space -> " "
    SoftBreak -> " "
    LineBreak -> "\n"
    Code _ t -> t
    Math _ t -> t
    _ -> ""
