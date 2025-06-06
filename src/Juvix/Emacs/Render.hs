module Juvix.Emacs.Render
  ( renderEmacs,
    nameKindFace,
    codeAnnFace,
  )
where

import Data.Text qualified as Text
import Juvix.Data.CodeAnn
import Juvix.Emacs.Point
import Juvix.Emacs.Properties
import Juvix.Emacs.SExp
import Juvix.Prelude

nameKindFace :: NameKind -> Maybe Face
nameKindFace = \case
  KNameConstructor -> Just FaceConstructor
  KNameInductive -> Just FaceInductive
  KNameFunction -> Just FaceFunction
  KNameTopModule -> Just FaceModule
  KNameLocalModule -> Just FaceModule
  KNameAxiom -> Just FaceAxiom
  KNameLocal -> Nothing
  KNameAlias -> Nothing
  KNameFixity -> Just FaceFixity

codeAnnFace :: CodeAnn -> Maybe Face
codeAnnFace = \case
  AnnKind k -> nameKindFace k
  AnnKeyword -> Just FaceKeyword
  AnnComment -> Just FaceComment
  AnnPragma -> Just FacePragma
  AnnJudoc -> Just FaceJudoc
  AnnDelimiter -> Just FaceDelimiter
  AnnLiteralString -> Just FaceString
  AnnLiteralInteger -> Just FaceNumber
  AnnError -> Just FaceError
  AnnCode -> Nothing
  AnnImportant -> Nothing
  AnnUnkindedSym -> Nothing
  AnnDef {} -> Nothing
  AnnRef {} -> Nothing

fromCodeAnn :: CodeAnn -> Maybe EmacsProperty
fromCodeAnn = \case
  AnnKind k -> face <$> nameKindFace k
  AnnKeyword -> Just (face FaceKeyword)
  AnnDelimiter -> Just (face FaceDelimiter)
  AnnComment -> Just (face FaceComment)
  AnnPragma -> Just (face FacePragma)
  AnnJudoc -> Just (face FaceJudoc)
  AnnLiteralString -> Just (face FaceString)
  AnnLiteralInteger -> Just (face FaceNumber)
  AnnError -> Just (face FaceError)
  AnnCode -> Nothing
  AnnImportant -> Nothing
  AnnUnkindedSym -> Nothing
  AnnDef {} -> Nothing
  AnnRef {} -> Nothing
  where
    face :: Face -> EmacsProperty
    face f = EPropertyFace (PropertyFace f)

data RenderState = RenderState
  { _statePoint :: Point,
    _stateText :: Text,
    _stateStack :: [(Point, EmacsProperty)],
    _stateProperties :: [WithRange EmacsProperty]
  }

makeLenses ''RenderState

renderEmacs :: Doc CodeAnn -> (Text, SExp)
renderEmacs s =
  let r =
        run
          . execState iniRenderState
          . go
          . alterAnnotationsS fromCodeAnn
          . layoutPretty defaultLayoutOptions
          $ s
   in (r ^. stateText, progn (map putProperty (r ^. stateProperties)))
  where
    iniRenderState =
      RenderState
        { _statePoint = minBound,
          _stateStack = [],
          _stateText = mempty,
          _stateProperties = []
        }
    go :: (Members '[State RenderState] r) => SimpleDocStream EmacsProperty -> Sem r ()
    go = \case
      SFail -> error "when is this supposed to happen?"
      SEmpty -> do
        st <- gets (^. stateStack)
        case st of
          [] -> return ()
          _ -> error "non-empty stack at the end. Is this possible?"
        return ()
      SChar ch rest -> do
        modify (over stateText (<> Text.singleton ch))
        modify (over statePoint succ)
        go rest
      SLine len rest -> do
        let b = "\n" <> Text.replicate len " "
        modify (over stateText (<> b))
        modify (over statePoint (pointSuccN (fromIntegral (succ len))))
        go rest
      SText len txt rest -> do
        modify (over stateText (<> txt))
        modify (over statePoint (pointSuccN (fromIntegral len)))
        go rest
      SAnnPush an rest -> do
        pt <- gets (^. statePoint)
        modify (over stateStack ((pt, an) :))
        go rest
      SAnnPop rest -> do
        _pintervalEnd <- gets (^. statePoint)
        (_pintervalStart, an) :| st <- nonEmpty' <$> gets (^. stateStack)
        modify (set stateStack st)
        let p =
              WithRange
                { _withRange = PointInterval {..},
                  _withRangeParam = an
                }
        modify (over stateProperties (p :))
        go rest
