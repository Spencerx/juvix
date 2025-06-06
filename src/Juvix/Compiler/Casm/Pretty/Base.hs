module Juvix.Compiler.Casm.Pretty.Base where

import Juvix.Compiler.Casm.Data.Result
import Juvix.Compiler.Casm.Language
import Juvix.Compiler.Casm.Pretty.Options
import Juvix.Data.CodeAnn
import Juvix.Extra.Strings qualified as Str

doc :: (PrettyCode c) => Options -> c -> Doc Ann
doc opts =
  run
    . runReader opts
    . ppCode

class PrettyCode c where
  ppCode :: (Member (Reader Options) r) => c -> Sem r (Doc Ann)

ppOffset :: Offset -> Sem r (Doc Ann)
ppOffset off = return $ annotate AnnLiteralInteger $ pretty off

ppIncAp :: Bool -> Sem r (Doc Ann)
ppIncAp = \case
  True -> return $ Str.semicolon <+> Str.apPlusPlus
  False -> mempty

ppComment :: Maybe Text -> Sem r (Doc Ann)
ppComment = \case
  Just c -> return $ Str.commentLineStart <+> pretty c <> hardline
  Nothing -> return mempty

instance PrettyCode Reg where
  ppCode = \case
    Ap -> return Str.ap
    Fp -> return Str.fp

ppWithOffset :: Offset -> Doc Ann -> Sem r (Doc Ann)
ppWithOffset off r
  | off == 0 =
      return r
  | off > 0 = do
      off' <- ppOffset off
      return $ r <+> Str.plus <+> off'
  | otherwise = do
      off' <- ppOffset (-off)
      return $ r <+> Str.minus <+> off'

instance PrettyCode Code where
  ppCode :: forall r. (Members '[Reader Options] r) => [Instruction] -> Sem r (Doc Ann)
  ppCode = mconcatMapM ppInstr
    where
      ppInstr :: Instruction -> Sem r (Doc Ann)
      ppInstr instr = do
        instr' <- ppCode instr
        return (ind instr' <> line)
        where
          ind = case instr of
            Label {} -> id
            _ -> indent'

instance PrettyCode Result where
  ppCode Result {..} = ppCode _resultCode

instance PrettyCode MemRef where
  ppCode MemRef {..} = do
    r <- ppCode _memRefReg
    r' <- ppWithOffset _memRefOff r
    return $ brackets r'

instance PrettyCode LabelRef where
  ppCode LabelRef {..} = case _labelRefName of
    Just n -> return $ annotate (AnnKind KNameFunction) $ pretty n
    Nothing -> return $ "label_" <> pretty (_labelRefSymbol ^. symbolId)

instance PrettyCode Value where
  ppCode = \case
    Imm i -> return $ annotate AnnLiteralInteger $ pretty i
    Ref r -> ppCode r
    Lab l -> ppCode l

instance PrettyCode RValue where
  ppCode = \case
    Val x -> ppCode x
    Load x -> ppCode x
    Binop x -> ppCode x

instance PrettyCode Opcode where
  ppCode = \case
    FieldAdd -> return Str.plus
    FieldMul -> return Str.mul

instance PrettyCode ExtraOpcode where
  ppCode = \case
    FieldSub -> return Str.minus
    FieldDiv -> return Str.div
    IntAdd -> return Str.iadd
    IntSub -> return Str.isub
    IntMul -> return Str.imul
    IntDiv -> return Str.idiv
    IntMod -> return Str.imod
    IntLt -> return Str.ilt

instance PrettyCode BinopValue where
  ppCode BinopValue {..} = do
    v1 <- ppCode _binopValueArg1
    case (_binopValueOpcode, _binopValueArg2) of
      (FieldAdd, Imm v) | v < 0 -> do
        v2 <- ppCode (Imm (-v))
        op <- ppCode FieldSub
        return $ v1 <+> op <+> v2
      _ -> do
        v2 <- ppCode _binopValueArg2
        op <- ppCode _binopValueOpcode
        return $ v1 <+> op <+> v2

instance PrettyCode LoadValue where
  ppCode LoadValue {..} = do
    src <- ppCode _loadValueSrc
    src' <- ppWithOffset _loadValueOff src
    return $ brackets src'

instance PrettyCode Hint where
  ppCode = \case
    HintInput var -> return $ "%{ Input(" <> pretty var <> ") %}"
    HintAlloc size -> return $ "%{ Alloc(" <> show size <> ") %}"
    HintRandomEcPoint -> return "%{ RandomEcPoint %}"

instance PrettyCode InstrAssign where
  ppCode InstrAssign {..} = do
    comment <- ppComment _instrAssignComment
    v <- ppCode _instrAssignValue
    r <- ppCode _instrAssignResult
    incAp <- ppIncAp _instrAssignIncAp
    return $ comment <> r <+> Str.equal <+> v <> incAp

instance PrettyCode InstrExtraBinop where
  ppCode InstrExtraBinop {..} = do
    comment <- ppComment _instrExtraBinopComment
    v1 <- ppCode _instrExtraBinopArg1
    v2 <- ppCode _instrExtraBinopArg2
    op <- ppCode _instrExtraBinopOpcode
    r <- ppCode _instrExtraBinopResult
    incAp <- ppIncAp _instrExtraBinopIncAp
    return $ comment <> r <+> Str.equal <+> v1 <+> op <+> v2 <> incAp

ppRel :: Bool -> RValue -> Sem r (Doc Ann)
ppRel isRel tgt
  | isLab tgt = return mempty
  | isRel = return $ Str.rel <> space
  | otherwise = return $ Str.abs <> space
  where
    isLab :: RValue -> Bool
    isLab = \case
      Val Lab {} -> True
      _ -> False

instance PrettyCode InstrJump where
  ppCode InstrJump {..} = do
    comment <- ppComment _instrJumpComment
    tgt <- ppCode _instrJumpTarget
    incAp <- ppIncAp _instrJumpIncAp
    rel <- ppRel _instrJumpRel _instrJumpTarget
    return $ comment <> Str.jmp <+> rel <> tgt <> incAp

instance PrettyCode InstrJumpIf where
  ppCode InstrJumpIf {..} = do
    comment <- ppComment _instrJumpIfComment
    tgt <- ppCode _instrJumpIfTarget
    v <- ppCode _instrJumpIfValue
    incAp <- ppIncAp _instrJumpIfIncAp
    return $ comment <> Str.jmp <+> tgt <+> Str.if_ <+> v <+> Str.notequal <+> annotate AnnLiteralInteger "0" <> incAp

instance PrettyCode InstrCall where
  ppCode InstrCall {..} = do
    comment <- ppComment _instrCallComment
    tgt <- ppCode _instrCallTarget
    rel <- ppRel _instrCallRel (Val _instrCallTarget)
    return $ comment <> Str.call <+> rel <> tgt

instance PrettyCode InstrAlloc where
  ppCode InstrAlloc {..} = do
    s <- ppCode _instrAllocSize
    return $ Str.ap <+> Str.plusequal <+> s

instance PrettyCode InstrAssert where
  ppCode InstrAssert {..} = do
    v <- ppCode _instrAssertValue
    return $ Str.assert_ <+> v

instance PrettyCode InstrTrace where
  ppCode InstrTrace {..} = do
    v <- ppCode _instrTraceValue
    return $ Str.trace_ <+> v

instance PrettyCode Instruction where
  ppCode = \case
    Assign x -> ppCode x
    ExtraBinop x -> ppCode x
    Jump x -> ppCode x
    JumpIf x -> ppCode x
    Call x -> ppCode x
    Return -> return Str.ret
    Alloc x -> ppCode x
    Assert x -> ppCode x
    Trace x -> ppCode x
    Hint x -> ppCode x
    Label x -> (<> colon) <$> ppCode x
    Nop -> return Str.nop
