module Juvix.Compiler.Core.Data.TransformationId.Strings where

import Juvix.Prelude

strLetHoisting :: Text
strLetHoisting = "let-hoisting"

strLoopHoisting :: Text
strLoopHoisting = "loop-hoisting"

strNormalizePipeline :: Text
strNormalizePipeline = "pipeline-normalize"

strStrippedPipeline :: Text
strStrippedPipeline = "pipeline-stripped"

strEvalPipeline :: Text
strEvalPipeline = "pipeline-eval"

strExecPipeline :: Text
strExecPipeline = "pipeline-exec"

strTypecheckPipeline :: Text
strTypecheckPipeline = "pipeline-typecheck"

strLifting :: Text
strLifting = "lifting"

strLetRecLifting :: Text
strLetRecLifting = "letrec-lifting"

strTopEtaExpand :: Text
strTopEtaExpand = "top-eta-expand"

strDetectConstantSideConditions :: Text
strDetectConstantSideConditions = "detect-constant-side-conditions"

strDetectRedundantPatterns :: Text
strDetectRedundantPatterns = "detect-redundant-patterns"

strMatchToCase :: Text
strMatchToCase = "match-to-case"

strEtaExpandApps :: Text
strEtaExpandApps = "eta-expand-apps"

strIdentity :: Text
strIdentity = "identity"

strRemoveTypeArgs :: Text
strRemoveTypeArgs = "remove-type-args"

strRemoveInductiveParams :: Text
strRemoveInductiveParams = "remove-inductive-params"

strMoveApps :: Text
strMoveApps = "move-apps"

strNatToPrimInt :: Text
strNatToPrimInt = "nat-to-primint"

strIntToPrimInt :: Text
strIntToPrimInt = "int-to-primint"

strConvertBuiltinTypes :: Text
strConvertBuiltinTypes = "convert-builtin-types"

strComputeTypeInfo :: Text
strComputeTypeInfo = "compute-type-info"

strComputeCaseANF :: Text
strComputeCaseANF = "compute-case-anf"

strUnrollRecursion :: Text
strUnrollRecursion = "unroll-recursion"

strDisambiguateNames :: Text
strDisambiguateNames = "disambiguate-names"

strCombineInfoTables :: Text
strCombineInfoTables = "combine-info-tables"

strCheckExec :: Text
strCheckExec = "check-exec"

strCheckRust :: Text
strCheckRust = "check-rust"

strCheckAnoma :: Text
strCheckAnoma = "check-anoma"

strCheckCairo :: Text
strCheckCairo = "check-cairo"

strNormalize :: Text
strNormalize = "normalize"

strLetFolding :: Text
strLetFolding = "let-folding"

strLambdaFolding :: Text
strLambdaFolding = "lambda-folding"

strInlining :: Text
strInlining = "inlining"

strMandatoryInlining :: Text
strMandatoryInlining = "mandatory-inlining"

strFoldTypeSynonyms :: Text
strFoldTypeSynonyms = "fold-type-synonyms"

strCaseCallLifting :: Text
strCaseCallLifting = "case-call-lifting"

strSimplifyIfs :: Text
strSimplifyIfs = "simplify-ifs"

strSimplifyComparisons :: Text
strSimplifyComparisons = "simplify-comparisons"

strSpecializeArgs :: Text
strSpecializeArgs = "specialize-args"

strCaseFolding :: Text
strCaseFolding = "case-folding"

strCasePermutation :: Text
strCasePermutation = "case-permutation"

strConstantFolding :: Text
strConstantFolding = "constant-folding"

strFilterUnreachable :: Text
strFilterUnreachable = "filter-unreachable"

strOptPhaseEval :: Text
strOptPhaseEval = "opt-phase-eval"

strOptPhaseExec :: Text
strOptPhaseExec = "opt-phase-exec"

strOptPhaseMain :: Text
strOptPhaseMain = "opt-phase-main"

strOptPhasePreLifting :: Text
strOptPhasePreLifting = "opt-phase-pre-lifting"

strTrace :: Text
strTrace = "trace"
