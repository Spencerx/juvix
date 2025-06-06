module Juvix.Compiler.Backend.Html.Extra where

import Juvix.Compiler.Backend.Html.Data.Options
import Juvix.Extra.Strings qualified as Str
import Juvix.Extra.Version
import Juvix.Prelude hiding (link)
import Text.Blaze.Html5 as Html hiding (map)
import Text.Blaze.Html5.Attributes qualified as Attr

mathJaxCdn :: (Members '[Reader HtmlOptions] r) => Sem r Html
mathJaxCdn = do
  assetsPrefix <- textValue <$> asks (^. htmlOptionsAssetsPrefix)
  let script1 =
        script
          ! Attr.src "https://polyfill.io/v3/polyfill.min.js?features=es6"
          $ mempty

      script2 =
        script
          ! Attr.type_ "text/javascript"
          ! Attr.id "MathJax-script"
          ! Attr.src (assetsPrefix <> "assets/js/tex-chtml.js")
          $ mempty
  return $ script1 <> script2

-- | This is useful fore debugging only. Note that it only works on a server
-- protocol, opening the file from the local system won't work. For that, one
-- can use @python3 -m http.server@.
livejs :: Html
livejs =
  script
    ! Attr.type_ "text/javascript"
    ! Attr.src "https://livejs.com/live.js"
    $ mempty

cssLink :: (Members '[Reader HtmlOptions] r) => AttributeValue -> Sem r Html
cssLink css = do
  assetsPrefix <- textValue <$> asks (^. htmlOptionsAssetsPrefix)
  return $
    link
      ! Attr.href (assetsPrefix <> "assets/css/" <> css)
      ! Attr.rel "stylesheet"
      ! Attr.type_ "text/css"

jsLink :: (Members '[Reader HtmlOptions] r) => AttributeValue -> Sem r Html
jsLink js = do
  assetsPrefix <- textValue <$> asks (^. htmlOptionsAssetsPrefix)
  return
    $ script
      ! Attr.src (assetsPrefix <> "assets/js/" <> js)
      ! Attr.type_ "text/javascript"
    $ mempty

toggleJs :: (Members '[Reader HtmlOptions] r) => Sem r Html
toggleJs = jsLink "toggle.js"

linuwialCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
linuwialCss = cssLink "linuwial.css"

juvixCatppuchinCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
juvixCatppuchinCss = cssLink "juvix-catppuchin.css"

juvixSourceCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
juvixSourceCss = cssLink "juvix-source.css"

juvixNordCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
juvixNordCss = cssLink "juvix-nord.css"

nordCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
nordCss = cssLink "nord.css"

latteLightCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
latteLightCss = cssLink "latte-light.css"

latteCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
latteCss = cssLink "latte.css"

macchiatoCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
macchiatoCss = cssLink "macchiato.css"

frappeCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
frappeCss = cssLink "frappe.css"

mochaCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
mochaCss = cssLink "mocha.css"

flavourCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
flavourCss = do
  theme <- asks (^. htmlOptionsTheme)
  case theme of
    Nord -> nordCss
    Macchiato -> macchiatoCss
    LatteLight -> latteLightCss
    Latte -> latteCss
    Frappe -> frappeCss
    Mocha -> mochaCss

themeCss :: (Members '[Reader HtmlOptions] r) => Sem r Html
themeCss = do
  theme <- asks (^. htmlOptionsTheme)
  case theme of
    Nord -> juvixNordCss
    Macchiato -> juvixCatppuchinCss
    LatteLight -> juvixCatppuchinCss
    Latte -> juvixCatppuchinCss
    Frappe -> juvixCatppuchinCss
    Mocha -> juvixCatppuchinCss

highlightJs :: (Members '[Reader HtmlOptions] r) => Sem r Html
highlightJs = jsLink "highlight.js"

metaUtf8 :: Html
metaUtf8 = meta ! Attr.charset "UTF-8"

taraSmiling :: (Members '[Reader HtmlOptions] r) => Sem r Html
taraSmiling = do
  assetsPrefix <- textValue <$> asks (^. htmlOptionsAssetsPrefix)
  return $
    Html.a ! Attr.href Str.juvixDotOrg $
      Html.img
        ! Attr.id "tara"
        ! Attr.src (assetsPrefix <> "assets/images/tara-smiling.svg")
        ! Attr.alt "Tara"

htmlJuvixFooter ::
  (Members '[Reader HtmlOptions] r) =>
  Sem r Html
htmlJuvixFooter = do
  noFooter <- asks (^. htmlOptionsNoFooter)
  htmlKind <- asks (^. htmlOptionsKind)
  tara <- taraSmiling
  if
      | noFooter -> return mempty
      | otherwise -> do
          let juvixLinkOrg :: Html
              juvixLinkOrg =
                a ! Attr.href Str.juvixDotOrg $
                  toHtml ("Juvix " :: Text)

              commitInfo :: Html
              commitInfo =
                a
                  ! Attr.href
                    (textValue ("https://github.com/anoma/juvix/commit/" <> commit))
                  $ toHtml fullVersionDoc

              juvixVersion :: Html
              juvixVersion =
                toHtml ("Powered by " :: Text)
                  <> juvixLinkOrg
                  <> commitInfo

          return $
            case htmlKind of
              HtmlDoc ->
                Html.div ! Attr.id "footer" $
                  p juvixVersion
                    <> tara
              _ -> footer . pre $ juvixVersion
