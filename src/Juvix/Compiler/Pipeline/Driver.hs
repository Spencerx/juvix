module Juvix.Compiler.Pipeline.Driver
  ( module Juvix.Compiler.Pipeline.Driver.Data,
    ModuleInfoCache,
    JvoCache,
    evalJvoCache,
    processFileUpTo,
    processProject,
    evalModuleInfoCachePackageDotJuvix,
    evalModuleInfoCacheSequential,
    evalModuleInfoCacheSetup,
    processFileToStoredCore,
    processFileUpToParsing,
    processModule,
    processImport,
    processRecursivelyUpToTyped,
    processRecursivelyUpTo,
    processProjectUpToScoping,
    processProjectUpToParsing,
  )
where

import Data.HashMap.Strict qualified as HashMap
import Data.HashSet qualified as HashSet
import Juvix.Compiler.Concrete.Data.Highlight
import Juvix.Compiler.Concrete.Language
import Juvix.Compiler.Concrete.Print.Base (docNoCommentsDefault)
import Juvix.Compiler.Concrete.Translation.FromParsed (scopeCheck)
import Juvix.Compiler.Concrete.Translation.FromParsed.Analysis.Scoping.Data.Context
import Juvix.Compiler.Concrete.Translation.FromParsed.Analysis.Scoping.Data.Context qualified as Scoper
import Juvix.Compiler.Concrete.Translation.FromSource (fromSource)
import Juvix.Compiler.Concrete.Translation.FromSource qualified as Parser
import Juvix.Compiler.Concrete.Translation.FromSource.Data.Context (ParserResult)
import Juvix.Compiler.Concrete.Translation.FromSource.Data.ParserState (parserStateImports)
import Juvix.Compiler.Concrete.Translation.FromSource.Data.ParserState qualified as Parser
import Juvix.Compiler.Concrete.Translation.FromSource.TopModuleNameChecker
import Juvix.Compiler.Core.Data.Module qualified as Core
import Juvix.Compiler.Core.Translation.FromInternal.Data.Context qualified as Core
import Juvix.Compiler.Internal.Translation.FromConcrete.Data.Context qualified as Internal
import Juvix.Compiler.Internal.Translation.FromInternal.Analysis.TypeChecking.Data.Context qualified as InternalTyped
import Juvix.Compiler.Pipeline
import Juvix.Compiler.Pipeline.Driver.Data
import Juvix.Compiler.Pipeline.JvoCache
import Juvix.Compiler.Pipeline.Loader.PathResolver
import Juvix.Compiler.Pipeline.ModuleInfoCache
import Juvix.Compiler.Pipeline.SHA256Cache
import Juvix.Compiler.Store.Core.Extra
import Juvix.Compiler.Store.Core.Extra qualified as Store
import Juvix.Compiler.Store.Extra
import Juvix.Compiler.Store.Extra qualified as Store
import Juvix.Compiler.Store.Language
import Juvix.Compiler.Store.Language qualified as Store
import Juvix.Compiler.Store.Options qualified as StoredModule
import Juvix.Compiler.Store.Options qualified as StoredOptions
import Juvix.Compiler.Store.Scoped.Language (ScopedModuleTable)
import Juvix.Compiler.Store.Scoped.Language qualified as Scoped
import Juvix.Compiler.Verification.Dumper
import Juvix.Data.CodeAnn
import Juvix.Extra.Serialize qualified as Serialize
import Juvix.Prelude
import Parallel.ProgressLog
import Path.Posix qualified as Path

processModule ::
  (Members '[ModuleInfoCache] r) =>
  EntryIndex ->
  Sem r (PipelineResult Store.ModuleInfo)
processModule = cacheGet

evalModuleInfoCacheSequential ::
  forall r a.
  ( Members
      '[ TaggedLock,
         HighlightBuilder,
         TopModuleNameChecker,
         Error JuvixError,
         Files,
         Dumper,
         Concurrent,
         Logger,
         Reader EntryPoint,
         Reader ImportTree,
         Reader PipelineOptions,
         PathResolver
       ]
      r
  ) =>
  Sem (ModuleInfoCache ': SHA256Cache ': ProgressLog ': JvoCache ': r) a ->
  Sem r a
evalModuleInfoCacheSequential = evalModuleInfoCacheSetup (const (void (compileSequentially)))

-- | Use only to compile package.juvix
evalModuleInfoCachePackageDotJuvix ::
  forall r a.
  ( Members
      '[ TaggedLock,
         HighlightBuilder,
         TopModuleNameChecker,
         Error JuvixError,
         Files,
         Concurrent,
         Logger,
         Reader Migration,
         PathResolver
       ]
      r
  ) =>
  Sem (ModuleInfoCache ': SHA256Cache ': ProgressLog ': JvoCache ': Dumper ': r) a ->
  Sem r a
evalModuleInfoCachePackageDotJuvix =
  ignoreDumper
    . evalJvoCache
    . ignoreProgressLog
    . evalSHA256Cache
    . evalCacheEmpty processModuleCacheMiss

-- | Compiles the whole project sequentially (i.e. all modules in the ImportTree).
compileSequentially ::
  forall r.
  ( Members
      '[ Files,
         SHA256Cache,
         ModuleInfoCache,
         Reader EntryPoint,
         PathResolver,
         Reader ImportTree
       ]
      r
  ) =>
  Sem r (HashMap ImportNode (PipelineResult Store.ModuleInfo))
compileSequentially = do
  nodes :: HashSet ImportNode <- asks (^. importTreeNodes)
  entry <- ask
  -- We should not compile the main file as a module
  let nodes' = HashSet.filter (not . isMainFile entry) nodes
  hashMapFromHashSetM nodes' (mkEntryIndex >=> compileNode)
  where
    isMainFile :: EntryPoint -> ImportNode -> Bool
    isMainFile entry node = Just (node ^. importNodeAbsFile) == entry ^. entryPointMainFile

compileNode ::
  (Members '[ModuleInfoCache, PathResolver] r) =>
  EntryIndex ->
  Sem r (PipelineResult Store.ModuleInfo)
compileNode e =
  withResolverRoot (e ^. entryIxImportNode . importNodePackageRoot)
  -- As opposed to parallel compilation, here we don't force the result
  $
    processModule e

-- | Used for parallel compilation
evalModuleInfoCacheSetup ::
  forall r a.
  ( Members
      '[ TaggedLock,
         Logger,
         HighlightBuilder,
         TopModuleNameChecker,
         Concurrent,
         Error JuvixError,
         Files,
         Dumper,
         Reader ImportTree,
         Reader PipelineOptions,
         PathResolver
       ]
      r
  ) =>
  (EntryIndex -> Sem (ModuleInfoCache ': SHA256Cache ': ProgressLog ': JvoCache ': r) ()) ->
  Sem (ModuleInfoCache ': SHA256Cache ': ProgressLog ': JvoCache ': r) a ->
  Sem r a
evalModuleInfoCacheSetup setup m = do
  evalJvoCache
    . runProgressLog
    . evalSHA256Cache
    . evalCacheEmptySetup setup (runMigration . processModuleCacheMiss)
    $ m

logDecision :: (Members '[ProgressLog] r) => ThreadId -> ImportNode -> ProcessModuleDecision x -> Sem r ()
logDecision _logItemThreadId _logItemModule dec = do
  let reason :: Maybe (Doc CodeAnn) = case dec of
        ProcessModuleReuse {} -> Nothing
        ProcessModuleRecompile r -> case r ^. recompileReason of
          RecompileNoJvoFile -> Nothing
          RecompileImportsChanged -> Just "Because an imported module changed"
          RecompileSourceChanged -> Just "Because the source changed"
          RecompileOptionsChanged -> Just "Because compilation options changed"

      msg :: Doc CodeAnn =
        docNoCommentsDefault (_logItemModule ^. importNodeTopModulePathKey)
          <+?> (parens <$> reason)

  progressLog
    LogItem
      { _logItemMessage = msg,
        _logItemAction = processModuleDecisionAction dec,
        _logItemThreadId,
        _logItemModule
      }

processModuleCacheMissDecide ::
  forall r rrecompile.
  ( Members
      '[ ModuleInfoCache,
         Error JuvixError,
         Files,
         Dumper,
         JvoCache,
         SHA256Cache,
         PathResolver
       ]
      r,
    Members
      '[ ModuleInfoCache,
         SHA256Cache,
         Error JuvixError,
         Reader Migration,
         Files,
         Dumper,
         TaggedLock,
         TopModuleNameChecker,
         HighlightBuilder,
         PathResolver
       ]
      rrecompile
  ) =>
  EntryIndex ->
  Sem r (ProcessModuleDecision rrecompile)
processModuleCacheMissDecide entryIx = do
  let entry = entryIx ^. entryIxEntry
      root = entry ^. entryPointRoot
      opts = StoredModule.fromEntryPoint entry
      buildDir = resolveAbsBuildDir root (entry ^. entryPointBuildDir)
      sourcePath = fromJust (entry ^. entryPointModulePath)
      relPath =
        fromJust
          . replaceExtension ".jvo"
          . fromJust
          $ stripProperPrefix $(mkAbsDir "/") sourcePath
      subdir = StoredOptions.getOptionsSubdir opts
      absPath = buildDir Path.</> subdir Path.</> relPath
      sha256 = fromJust (entry ^. entryPointSHA256)

  let recompile :: Sem rrecompile (PipelineResult Store.ModuleInfo)
      recompile = do
        res <- processModuleToStoredCore entry
        Serialize.saveToFile absPath (res ^. pipelineResult)
        return res

      recompileWithReason :: RecompileReason -> ProcessModuleDecision rrecompile
      recompileWithReason reason =
        ProcessModuleRecompile
          Recompile
            { _recompileDo = recompile,
              _recompileReason = reason
            }

  runErrorWith (return . recompileWithReason) $ do
    info :: Store.ModuleInfo <- loadFromJvoFile absPath >>= errorMaybe RecompileNoJvoFile

    unless (info ^. Store.moduleInfoSHA256 == sha256) (throw RecompileSourceChanged)
    unless (info ^. Store.moduleInfoOptions == opts) (throw RecompileOptionsChanged)
    CompileResult {..} <- runReader entry (processImports (info ^. Store.moduleInfoImports))
    if
        | _compileResultChanged -> throw RecompileImportsChanged
        | otherwise ->
            return $
              ProcessModuleReuse
                PipelineResult
                  { _pipelineResult = info,
                    _pipelineResultImports = _compileResultModuleTable,
                    _pipelineResultImportTables = _compileResultImportTables,
                    _pipelineResultChanged = False
                  }

processModuleCacheMiss ::
  forall r.
  ( Members
      '[ ModuleInfoCache,
         TaggedLock,
         HighlightBuilder,
         TopModuleNameChecker,
         Error JuvixError,
         Files,
         Dumper,
         JvoCache,
         SHA256Cache,
         Reader Migration,
         ProgressLog,
         Concurrent,
         PathResolver
       ]
      r
  ) =>
  EntryIndex ->
  Sem r (PipelineResult Store.ModuleInfo)
processModuleCacheMiss entryIx = do
  p <- processModuleCacheMissDecide entryIx
  tid <- myThreadId
  logDecision tid (entryIx ^. entryIxImportNode) p
  case p of
    ProcessModuleReuse r -> do
      highlightMergeDocTable (r ^. pipelineResult . Store.moduleInfoScopedModule . Scoped.scopedModuleDocTable)
      return r
    ProcessModuleRecompile recomp -> do
      recomp ^. recompileDo

processProject ::
  (Members '[Files, PathResolver, SHA256Cache, ModuleInfoCache, Reader EntryPoint, Reader ImportTree] r) =>
  Sem r [ProcessedNode ()]
processProject = do
  rootDir <- asks (^. entryPointRoot)
  nodes <- asks (importTreeProjectNodes rootDir)
  map mkProcessed <$> forWithM nodes (mkEntryIndex >=> processModule)
  where
    mkProcessed :: (ImportNode, PipelineResult ModuleInfo) -> ProcessedNode ()
    mkProcessed (_processedNode, _processedNodeInfo) =
      ProcessedNode
        { _processedNodeData = (),
          ..
        }

processProjectWith ::
  forall a r.
  ( Members
      '[ Error JuvixError,
         SHA256Cache,
         ModuleInfoCache,
         Reader Migration,
         PathResolver,
         Reader EntryPoint,
         Reader MainPackageId,
         Reader ImportTree,
         Files
       ]
      r
  ) =>
  ( forall r'.
    ( Members
        '[ Error JuvixError,
           Files,
           Reader Migration,
           Reader PackageId,
           Reader MainPackageId,
           HighlightBuilder,
           PathResolver
         ]
        r'
    ) =>
    ProcessedNode () ->
    Sem r' a
  ) ->
  Sem r [ProcessedNode a]
processProjectWith procNode = do
  l <- processProject
  pkgId <- asks (^. entryPointPackageId)
  runReader pkgId $
    sequence
      [ do
          d <-
            withResolverRoot (n ^. processedNode . importNodePackageRoot)
              . evalHighlightBuilder
              $ procNode n
          return (set processedNodeData d n)
        | n <- l
      ]

processProjectUpToScoping ::
  forall r.
  ( Members
      '[ Files,
         Error JuvixError,
         Reader Migration,
         PathResolver,
         SHA256Cache,
         ModuleInfoCache,
         Reader EntryPoint,
         Reader MainPackageId,
         Reader ImportTree
       ]
      r
  ) =>
  Sem r [ProcessedNode ScoperResult]
processProjectUpToScoping = processProjectWith processNodeUpToScoping

processProjectUpToParsing ::
  forall r.
  ( Members
      '[ Files,
         Error JuvixError,
         PathResolver,
         Reader Migration,
         Reader MainPackageId,
         SHA256Cache,
         ModuleInfoCache,
         Reader EntryPoint,
         Reader ImportTree
       ]
      r
  ) =>
  Sem r [ProcessedNode ParserResult]
processProjectUpToParsing = processProjectWith processNodeUpToParsing

processNodeUpToParsing ::
  ( Members
      '[ PathResolver,
         Error JuvixError,
         Files,
         HighlightBuilder,
         Reader PackageId
       ]
      r
  ) =>
  ProcessedNode () ->
  Sem r ParserResult
processNodeUpToParsing node =
  runTopModuleNameChecker $
    fromSource False Nothing (Just (node ^. processedNode . importNodeAbsFile))

processNodeUpToScoping ::
  ( Members
      '[ PathResolver,
         Error JuvixError,
         Reader Migration,
         Files,
         HighlightBuilder,
         Reader PackageId,
         Reader MainPackageId
       ]
      r
  ) =>
  ProcessedNode () ->
  Sem r ScoperResult
processNodeUpToScoping node = do
  parseRes <- processNodeUpToParsing node
  pkg <- ask @PackageId
  let modules = node ^. processedNodeInfo . pipelineResultImports
      scopedModules :: ScopedModuleTable = getScopedModuleTable modules
      tmp :: TopModulePathKey = relPathtoTopModulePathKey (node ^. processedNode . importNodeFile)
      moduleid :: ModuleId = run (runReader pkg (getModuleId tmp))
  evalTopNameIdGen moduleid $
    scopeCheck scopedModules parseRes

processRecursivelyUpTo ::
  forall a r.
  ( Members
      '[ Reader EntryPoint,
         Error JuvixError,
         TopModuleNameChecker,
         PathResolver,
         Files,
         HighlightBuilder,
         SHA256Cache,
         ModuleInfoCache
       ]
      r
  ) =>
  (ImportNode -> Bool) ->
  Sem (Reader Parser.ParserResult ': Reader Store.ModuleTable ': NameIdGen ': r) a ->
  Sem r (a, [a])
processRecursivelyUpTo shouldRecurse upto = do
  entry <- ask
  PipelineResult {..} <- processFileUpToParsing entry
  let imports = HashMap.keys (_pipelineResultImports ^. Store.moduleTable)
  ms <- fmap catMaybes . forM imports $ \imp ->
    withPathFile imp goImport
  let pkg = entry ^. entryPointPackageId
  mid <- runReader pkg (getModuleId (_pipelineResult ^. Parser.resultModule . modulePath . to topModulePathKey))
  res <-
    evalTopNameIdGen mid
      . runReader _pipelineResultImports
      . runReader _pipelineResult
      $ upto
  return (res, ms)
  where
    goImport :: ImportNode -> Sem r (Maybe a)
    goImport node
      | shouldRecurse node = do
          pkgInfo <- fromJust . HashMap.lookup (node ^. importNodePackageRoot) <$> getPackageInfos
          let pid = pkgInfo ^. packageInfoPackageId
          entry <- ask
          let entry' =
                entry
                  { _entryPointStdin = Nothing,
                    _entryPointResolverRoot = node ^. importNodePackageRoot,
                    _entryPointRoot = node ^. importNodePackageRoot,
                    _entryPointPackageId = pid,
                    _entryPointModulePath = Just (node ^. importNodeAbsFile)
                  }
          (Just . (^. pipelineResult)) <$> local (const entry') (processFileUpTo upto)
      | otherwise = return Nothing

processRecursivelyUpToTyped ::
  forall r.
  ( Members
      '[ Reader EntryPoint,
         TopModuleNameChecker,
         Reader Migration,
         TaggedLock,
         HighlightBuilder,
         Error JuvixError,
         Files,
         PathResolver,
         SHA256Cache,
         ModuleInfoCache
       ]
      r
  ) =>
  Sem r (InternalTyped.InternalTypedResult, [InternalTyped.InternalTypedResult])
processRecursivelyUpToTyped = processRecursivelyUpTo (const True) upToInternalTyped

processImport ::
  forall r.
  (Members '[SHA256Cache, ModuleInfoCache, Reader EntryPoint, Error JuvixError, Files, PathResolver] r) =>
  TopModulePath ->
  Sem r (PipelineResult Store.ModuleInfo)
processImport p = withPathFile p getCachedImport
  where
    getCachedImport :: ImportNode -> Sem r (PipelineResult Store.ModuleInfo)
    getCachedImport = mkEntryIndex >=> processModule

processFileUpToParsing ::
  forall r.
  (Members '[SHA256Cache, ModuleInfoCache, HighlightBuilder, TopModuleNameChecker, Error JuvixError, Files, PathResolver] r) =>
  EntryPoint ->
  Sem r (PipelineResult Parser.ParserResult)
processFileUpToParsing entry = do
  res <- runReader entry upToParsing
  let imports :: [Import 'Parsed] = res ^. Parser.resultParserState . Parser.parserStateImports
  CompileResult {..} <- runReader entry (processImports (map (^. importModulePath) imports))
  return
    PipelineResult
      { _pipelineResult = res,
        _pipelineResultImports = _compileResultModuleTable,
        _pipelineResultImportTables = _compileResultImportTables,
        _pipelineResultChanged = True
      }

processFileUpTo ::
  forall r a.
  (Members '[Reader EntryPoint, Error JuvixError, TopModuleNameChecker, PathResolver, Files, HighlightBuilder, SHA256Cache, ModuleInfoCache] r) =>
  Sem (Reader Parser.ParserResult ': Reader Store.ModuleTable ': NameIdGen ': r) a ->
  Sem r (PipelineResult a)
processFileUpTo a = do
  entry <- ask
  res <- processFileUpToParsing entry
  let pkg = entry ^. entryPointPackageId
  mid <- runReader pkg (getModuleId (res ^. pipelineResult . Parser.resultModule . modulePath . to topModulePathKey))
  a' <-
    evalTopNameIdGen mid
      . runReader (res ^. pipelineResultImports)
      . runReader (res ^. pipelineResult)
      $ a
  return (set pipelineResult a' res)

processImports ::
  forall r.
  (Members '[Reader EntryPoint, SHA256Cache, ModuleInfoCache, Error JuvixError, Files, PathResolver] r) =>
  [TopModulePath] ->
  Sem r CompileResult
processImports imports = do
  ms :: [PipelineResult Store.ModuleInfo] <- forM imports processImport
  let mtab =
        Store.mkModuleTable (map (^. pipelineResult) ms)
          <> mconcatMap (^. pipelineResultImports) ms
      changed = any (^. pipelineResultChanged) ms
      itabs =
        HashMap.fromList
          . map computeImportsTable
          $ ms
  return
    CompileResult
      { _compileResultChanged = changed,
        _compileResultModuleTable = mtab,
        _compileResultImportTables =
          itabs
            <> mconcatMap (^. pipelineResultImportTables) ms
      }
  where
    computeImportsTable :: PipelineResult Store.ModuleInfo -> (ModuleId, Core.InfoTable)
    computeImportsTable r =
      ( mid,
        Store.toCore (r ^. pipelineResult . Store.moduleInfoCoreTable)
          <> mconcat (HashMap.elems (r ^. pipelineResultImportTables))
      )
      where
        mid = r ^. pipelineResult . Store.moduleInfoInternalModule . Internal.internalModuleId

processModuleToStoredCore ::
  forall r.
  (Members '[Reader Migration, SHA256Cache, ModuleInfoCache, PathResolver, HighlightBuilder, TopModuleNameChecker, Error JuvixError, Files, Dumper] r) =>
  EntryPoint ->
  Sem r (PipelineResult Store.ModuleInfo)
processModuleToStoredCore entry = do
  over pipelineResult mkModuleInfo <$> processFileToStoredCore entry
  where
    mkModuleInfo :: Core.CoreResult -> Store.ModuleInfo
    mkModuleInfo Core.CoreResult {..} =
      Store.ModuleInfo
        { _moduleInfoScopedModule = scoperResult ^. Scoper.resultScopedModule,
          _moduleInfoInternalModule = _coreResultInternalTypedResult ^. InternalTyped.resultInternalModule,
          _moduleInfoCoreTable = fromCore (_coreResultModule ^. Core.moduleInfoTable),
          _moduleInfoImports = map (^. importModulePath) $ scoperResult ^. Scoper.resultParserResult . Parser.resultParserState . parserStateImports,
          _moduleInfoOptions = StoredOptions.fromEntryPoint entry,
          _moduleInfoSHA256 = fromJust (entry ^. entryPointSHA256)
        }
      where
        scoperResult = _coreResultInternalTypedResult ^. InternalTyped.resultInternal . Internal.resultScoper

processFileToStoredCore ::
  forall r.
  (Members '[Reader Migration, SHA256Cache, ModuleInfoCache, HighlightBuilder, PathResolver, TopModuleNameChecker, Error JuvixError, Files, Dumper] r) =>
  EntryPoint ->
  Sem r (PipelineResult Core.CoreResult)
processFileToStoredCore entry = do
  res <- processFileUpToParsing entry
  let pkg = entry ^. entryPointPackageId
  mid <- runReader pkg (getModuleId (res ^. pipelineResult . Parser.resultModule . modulePath . to topModulePathKey))
  r <-
    evalTopNameIdGen mid
      . runReader entry
      . runReader (res ^. pipelineResultImports)
      . runReader (res ^. pipelineResult)
      $ upToStoredCore
  return (set pipelineResult r res)
