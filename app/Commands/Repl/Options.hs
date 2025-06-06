module Commands.Repl.Options where

import CommonOptions
import Juvix.Compiler.Core.Pretty.Options qualified as Core
import Juvix.Compiler.Core.Transformation

data ReplOptions = ReplOptions
  { _replIsDev :: Bool,
    _replInputFile :: Maybe (AppPath File),
    _replShowDeBruijn :: Bool,
    _replNoPrelude :: Bool,
    _replTransformations :: [TransformationId],
    _replNoDisambiguate :: Bool,
    _replPrintValues :: Bool
  }
  deriving stock (Data)

makeLenses ''ReplOptions

instance CanonicalProjection ReplOptions Core.Options where
  project c =
    Core.defaultOptions
      { Core._optShowDeBruijnIndices = c ^. replShowDeBruijn
      }

parseRepl :: Parser ReplOptions
parseRepl = do
  let _replTransformations = toEvalTransformations
      _replShowDeBruijn = False
      _replNoDisambiguate = False
      _replPrintValues = True
      _replIsDev = False
  _replInputFile <- optional (parseInputFile FileExtJuvix)
  _replNoPrelude <-
    switch
      ( long "no-prelude"
          <> help "Do not load the Prelude module on launch"
      )
  pure ReplOptions {..}
