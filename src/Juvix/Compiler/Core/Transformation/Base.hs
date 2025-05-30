-- | Transformations operate on a module. They transform the info table of the
-- module. The imports table is used for symbol/tag lookup but never modified.
module Juvix.Compiler.Core.Transformation.Base
  ( module Juvix.Compiler.Core.Transformation.Base,
    module Juvix.Compiler.Core.Data.InfoTable,
    module Juvix.Compiler.Core.Data.Module,
    module Juvix.Compiler.Core.Language,
  )
where

import Data.HashMap.Strict qualified as HashMap
import Juvix.Compiler.Core.Data.InfoTable
import Juvix.Compiler.Core.Data.InfoTableBuilder
import Juvix.Compiler.Core.Data.Module
import Juvix.Compiler.Core.Extra.Base
import Juvix.Compiler.Core.Language
import Juvix.Compiler.Core.Options

mapIdentsM :: (Monad m) => (IdentifierInfo -> m IdentifierInfo) -> Module -> m Module
mapIdentsM = overM (moduleInfoTable . infoIdentifiers) . mapM

mapInductivesM :: (Monad m) => (InductiveInfo -> m InductiveInfo) -> Module -> m Module
mapInductivesM = overM (moduleInfoTable . infoInductives) . mapM

mapConstructorsM :: (Monad m) => (ConstructorInfo -> m ConstructorInfo) -> Module -> m Module
mapConstructorsM = overM (moduleInfoTable . infoConstructors) . mapM

mapNodesM :: (Monad m) => (Node -> m Node) -> Module -> m Module
mapNodesM = overM (moduleInfoTable . identContext) . mapM

mapAllNodesM :: (Monad m) => (Node -> m Node) -> Module -> m Module
mapAllNodesM f tab =
  mapNodesM f tab
    >>= mapConstructorsM (overM constructorType f)
    >>= mapInductivesM (overM inductiveKind f)
    >>= mapIdentsM (overM identifierType f)

mapIdents :: (IdentifierInfo -> IdentifierInfo) -> Module -> Module
mapIdents = over (moduleInfoTable . infoIdentifiers) . fmap

mapInductives :: (InductiveInfo -> InductiveInfo) -> Module -> Module
mapInductives = over (moduleInfoTable . infoInductives) . fmap

mapConstructors :: (ConstructorInfo -> ConstructorInfo) -> Module -> Module
mapConstructors = over (moduleInfoTable . infoConstructors) . fmap

mapT :: (Symbol -> Node -> Node) -> Module -> Module
mapT f = over (moduleInfoTable . identContext) (HashMap.mapWithKey f)

mapT' :: (Symbol -> Node -> Sem (InfoTableBuilder ': r) Node) -> Module -> Sem r Module
mapT' f m =
  fmap fst $
    runInfoTableBuilder m $
      mapM_
        (\(k, v) -> f k v >>= registerIdentNode k)
        (HashMap.toList (m ^. moduleInfoTable . identContext))

walkT :: (Applicative f) => (Symbol -> Node -> f ()) -> InfoTable -> f ()
walkT f tab = for_ (HashMap.toList (tab ^. identContext)) (uncurry f)

mapAllNodes :: (Node -> Node) -> Module -> Module
mapAllNodes f md =
  mapInductives convertInductive
    . mapConstructors convertConstructor
    . mapIdents convertIdent
    $ mapT (const f) md
  where
    convertIdent :: IdentifierInfo -> IdentifierInfo
    convertIdent ii =
      ii
        { _identifierType = f (ii ^. identifierType)
        }

    convertConstructor :: ConstructorInfo -> ConstructorInfo
    convertConstructor = over constructorType f

    convertInductive :: InductiveInfo -> InductiveInfo
    convertInductive ii =
      ii
        { _inductiveKind = kind',
          _inductiveParams = zipWithExact (set paramKind) params' (ii ^. inductiveParams)
        }
      where
        nParams = length (ii ^. inductiveParams)
        kind' = f (ii ^. inductiveKind)
        params' = take nParams (typeArgs kind')

withOptimizationLevel :: (Member (Reader CoreOptions) r) => Int -> (Module -> Sem r Module) -> Module -> Sem r Module
withOptimizationLevel n f tab = do
  l <- asks (^. optOptimizationLevel)
  if
      | l >= n -> f tab
      | otherwise -> return tab

withOptimizationLevel' :: (Member (Reader CoreOptions) r) => Module -> Int -> (Module -> Sem r Module) -> Sem r Module
withOptimizationLevel' tab n f = withOptimizationLevel n f tab
