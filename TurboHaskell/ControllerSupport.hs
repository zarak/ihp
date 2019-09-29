{-# LANGUAGE TypeSynonymInstances, FlexibleInstances, TypeFamilies, ConstrainedClassMethods, ScopedTypeVariables, FunctionalDependencies, AllowAmbiguousTypes #-}

module TurboHaskell.ControllerSupport (Action, Action', SimpleAction, cs, (|>), getRequestBody, getRequestUrl, getHeader, RequestContext (..), getRequest, requestHeaders, getFiles, Controller (..), runAction, createRequestContext, ControllerContext, fromControllerContext, maybeFromControllerContext, InitControllerContext (..), ControllerApplicationMap, runActionWithNewContext, emptyControllerContext) where
import ClassyPrelude
import TurboHaskell.HaskellSupport
import Data.String.Conversions (cs)
import Network.Wai (Response, Request, ResponseReceived, responseLBS, requestBody, queryString, requestHeaders)
import qualified Network.Wai
import TurboHaskell.ModelSupport
import TurboHaskell.ApplicationContext (ApplicationContext (..))
import qualified TurboHaskell.ApplicationContext as ApplicationContext
import Network.Wai.Parse as WaiParse
import qualified Data.ByteString.Lazy
import Data.Maybe (fromJust)
import qualified Data.Text.Read
import qualified Data.Either
import qualified Data.Text.Encoding
import qualified Data.Text
import qualified Data.Aeson
import TurboHaskell.Controller.RequestContext
import qualified Data.CaseInsensitive

import qualified Text.Blaze.Html.Renderer.Utf8 as Blaze
import Text.Blaze.Html (Html)

import Database.PostgreSQL.Simple as PG

import Control.Monad.Reader

import Network.Wai.Session (Session)
import qualified Data.Vault.Lazy         as Vault
import qualified Data.TMap as TypeMap

type Action controllerContext = ((?requestContext :: RequestContext, ?modelContext :: ModelContext, ?controllerContext :: controllerContext) => IO ResponseReceived)
type SimpleAction = Action ()
type Action' = IO ResponseReceived

-- type ActionHelper return = ((?requestContext :: RequestContext, ?modelContext :: ModelContext, ?controllerContext :: controllerContext) => return)

--request :: StateT RequestContext IO ResponseReceived -> Request
--request = do
--    RequestContext request <- get
--    return request

--(|>) :: a -> f -> f a

newtype ControllerContext = ControllerContext TypeMap.TMap
type family ControllerApplicationMap controller

{-# INLINE fromControllerContext #-}
fromControllerContext :: forall a. (?controllerContext :: ControllerContext, Typeable a) => a
fromControllerContext =
    let
        (ControllerContext context) = ?controllerContext
        notFoundMessage = ("Unable to find value in controller context: " <> show context)
    in
        fromMaybe (error notFoundMessage) (maybeFromControllerContext @a)

{-# INLINE maybeFromControllerContext #-}
maybeFromControllerContext :: forall a. (?controllerContext :: ControllerContext, Typeable a) => Maybe a
maybeFromControllerContext = let (ControllerContext context) = ?controllerContext in TypeMap.lookup @a context

{-# INLINE emptyControllerContext #-}
emptyControllerContext :: ControllerContext
emptyControllerContext = ControllerContext TypeMap.empty

class Controller controller where
    beforeAction :: (?controllerContext :: ControllerContext, ?modelContext :: ModelContext, ?requestContext :: RequestContext, ?theAction :: controller) => IO ()
    beforeAction = return ()
    action :: (?controllerContext :: ControllerContext, ?modelContext :: ModelContext, ?requestContext :: RequestContext, ?theAction :: controller) => controller -> IO ResponseReceived

class InitControllerContext application where
    initContext :: (?modelContext :: ModelContext, ?requestContext :: RequestContext) => TypeMap.TMap -> IO TypeMap.TMap

{-# INLINE runAction #-}
runAction :: forall controller. (Controller controller, ?applicationContext :: ApplicationContext, ?requestContext :: RequestContext, ?controllerContext :: ControllerContext, ?modelContext :: ModelContext) => controller -> IO ResponseReceived
runAction controller = do
    let ?theAction = controller
    beforeAction >> action controller

{-# INLINE runActionWithNewContext #-}
runActionWithNewContext :: forall controller. (Controller controller, ?applicationContext :: ApplicationContext, ?requestContext :: RequestContext, InitControllerContext (ControllerApplicationMap controller)) => controller -> IO ResponseReceived
runActionWithNewContext controller = do
    let ?modelContext = ApplicationContext.modelContext ?applicationContext
    context <- initContext @(ControllerApplicationMap controller) TypeMap.empty
    let ?controllerContext = ControllerContext context
    runAction controller


{-# INLINE getRequestBody #-}
getRequestBody :: (?requestContext :: RequestContext) => IO ByteString
getRequestBody =
    let (RequestContext request _ _ _ _) = ?requestContext
    in Network.Wai.requestBody request

{-# INLINE getRequestUrl #-}
getRequestUrl :: (?requestContext :: RequestContext) => ByteString
getRequestUrl =
    let (RequestContext request _ _ _ _) = ?requestContext
    in Network.Wai.rawPathInfo request

{-# INLINE getHeader #-}
getHeader :: (?requestContext :: RequestContext) => ByteString -> Maybe ByteString
getHeader name =
    let (RequestContext request _ _ _ _) = ?requestContext
    in lookup (Data.CaseInsensitive.mk name) (Network.Wai.requestHeaders request)

{-# INLINE getRequest #-}
getRequest :: (?requestContext :: RequestContext) => Network.Wai.Request
getRequest =
    let (RequestContext request _ _ _ _) = ?requestContext
    in request

{-# INLINE getFiles #-}
getFiles :: (?requestContext :: RequestContext) => [File Data.ByteString.Lazy.ByteString]
getFiles =
    let (RequestContext _ _ _ files _) = ?requestContext
    in files

{-# INLINE createRequestContext #-}
createRequestContext :: ApplicationContext -> Request -> Respond -> IO RequestContext
createRequestContext ApplicationContext { session } request respond = do
    (params, files) <- WaiParse.parseRequestBodyEx WaiParse.defaultParseRequestBodyOptions WaiParse.lbsBackEnd request
    return (RequestContext request respond params files session)
