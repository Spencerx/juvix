module Juvix.Compiler.Store.Language where

import Juvix.Compiler.Concrete.Data.Name
import Juvix.Compiler.Store.Core.Data.InfoTable qualified as Core
import Juvix.Compiler.Store.Internal.Language
import Juvix.Compiler.Store.Options
import Juvix.Compiler.Store.Scoped.Language
import Juvix.Extra.Serialize
import Juvix.Prelude

data ModuleInfo = ModuleInfo
  { _moduleInfoScopedModule :: ScopedModule,
    _moduleInfoInternalModule :: InternalModule,
    _moduleInfoCoreTable :: Core.InfoTable,
    _moduleInfoImports :: [TopModulePath],
    _moduleInfoOptions :: Options,
    _moduleInfoSHA256 :: Text
  }
  deriving stock (Generic)

instance Serialize ModuleInfo

instance NFData ModuleInfo

newtype ModuleTable = ModuleTable
  { _moduleTable :: HashMap TopModulePath ModuleInfo
  }
  deriving newtype (Semigroup, Monoid)
  deriving stock (Generic)

makeLenses ''ModuleInfo
makeLenses ''ModuleTable

instance NFData ModuleTable
