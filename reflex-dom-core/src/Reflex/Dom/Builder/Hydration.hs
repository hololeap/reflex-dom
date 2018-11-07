{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
#ifdef USE_TEMPLATE_HASKELL
{-# LANGUAGE TemplateHaskell #-}
#endif
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
#ifdef ghcjs_HOST_OS
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE JavaScriptFFI #-}
#endif
module Reflex.Dom.Builder.Hydration
       ( EventTriggerRef (..)
       , HydrationDomBuilderEnv (..)
       , HydrationDomBuilderT (..)
       , HydrationMode (..)
       , runHydrationDomBuilderT
       , askParent
       , askEvents
       , append
       , textNodeInternal
       , deleteBetweenExclusive
       , extractBetweenExclusive
       , deleteUpTo
       , extractUpTo
       , SupportsHydrationDomBuilder
       , collectUpTo
       , collectUpToGivenParent
       , EventFilterTriggerRef (..)
       , wrap
       , makeElement
       , GhcjsDomHandler (..)
       , GhcjsDomHandler1 (..)
       , GhcjsDomEvent (..)
       , GhcjsEventFilter (..)
       , Pair1 (..)
       , Maybe1 (..)
       , GhcjsEventSpec (..)
       , HasDocument (..)
       , ghcjsEventSpec_filters
       , ghcjsEventSpec_handler
       , GhcjsEventHandler (..)
#ifndef USE_TEMPLATE_HASKELL
       , phantom2
#endif
       , drawChildUpdate
       , ChildReadyState (..)
       , ChildReadyStateInt (..)
       , mkHasFocus
       , insertBefore
       , EventType
       , defaultDomEventHandler
       , defaultDomWindowEventHandler
       , withIsEvent
       , showEventName
       , elementOnEventName
       , windowOnEventName
       , wrapDomEvent
       , subscribeDomEvent
       -- * Internal
       , traverseDMapWithKeyWithAdjust'
       , hoistTraverseWithKeyWithAdjust
       , traverseIntMapWithKeyWithAdjust'
       , hoistTraverseIntMapWithKeyWithAdjust
       ) where

import Foreign.JavaScript.TH
import Reflex.Adjustable.Class
import Reflex.Class as Reflex
import qualified Reflex.Spider.Internal as Spider
import Reflex.Dom.Builder.Class
import Reflex.Dom.Builder.Immediate hiding (askParent, append, extractBetweenExclusive, extractUpTo, collectUpToGivenParent, askEvents, wrap, makeElement, textNodeInternal, commentNodeInternal, wrapDomEvent, mkHasFocus, insertBefore, deleteBetweenExclusive, traverseIntMapWithKeyWithAdjust', traverseDMapWithKeyWithAdjust', hoistTraverseWithKeyWithAdjust, deleteUpTo, collectUpTo, hoistTraverseIntMapWithKeyWithAdjust, drawChildUpdate, subscribeDomEvent)
import Reflex.Dynamic
import Reflex.Host.Class
import qualified Reflex.Patch.DMap as PatchDMap
import qualified Reflex.Patch.DMapWithMove as PatchDMapWithMove
import Reflex.PerformEvent.Class
import Reflex.PostBuild.Class
import Reflex.TriggerEvent.Base hiding (askEvents)
import qualified Reflex.TriggerEvent.Base as TriggerEventT (askEvents)
import Reflex.TriggerEvent.Class

import Control.Concurrent
import Control.Lens hiding (element, ix)
import Control.Monad.Exception
import Control.Monad.Primitive
import Control.Monad.Reader
import Control.Monad.Ref
import Control.Monad.State.Strict
#ifndef USE_TEMPLATE_HASKELL
import Data.Functor.Contravariant (phantom)
#endif
import Data.Bitraversable
import Data.Default
import Data.Dependent.Map (DMap)
import qualified Data.Dependent.Map as DMap
import Data.Dependent.Sum
import Data.Functor.Compose
import Data.Functor.Constant
import Data.Functor.Misc
import Data.Functor.Product
import Data.IORef
import qualified Data.Map as Map
import Data.Maybe
import Data.Monoid hiding (Product)
import Data.Some (Some)
import qualified Data.Some as Some
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Typeable, typeRep)
import GHC.Generics (Generic)
import qualified GHCJS.DOM as DOM
import GHCJS.DOM.Document (Document, createDocumentFragment, createElement, createElementNS, createTextNode, createComment)
import GHCJS.DOM.Element (getScrollTop, removeAttribute, removeAttributeNS, setAttribute, setAttributeNS, hasAttribute, hasAttributeNS)
import qualified GHCJS.DOM.Element as Element
import qualified GHCJS.DOM.Event as Event
import qualified GHCJS.DOM.GlobalEventHandlers as Events
import qualified GHCJS.DOM.DocumentAndElementEventHandlers as Events
import GHCJS.DOM.EventM (EventM, event, on)
import qualified GHCJS.DOM.EventM as DOM
import qualified GHCJS.DOM.FileList as FileList
import qualified GHCJS.DOM.HTMLInputElement as Input
import qualified GHCJS.DOM.HTMLSelectElement as Select
import qualified GHCJS.DOM.HTMLTextAreaElement as TextArea
import GHCJS.DOM.MouseEvent
import qualified GHCJS.DOM.Touch as Touch
import qualified GHCJS.DOM.TouchEvent as TouchEvent
import qualified GHCJS.DOM.TouchList as TouchList
import GHCJS.DOM.Node (appendChild_, getChildNodes, getOwnerDocumentUnchecked, getParentNodeUnchecked, setNodeValue, toNode)
import qualified GHCJS.DOM.Node as DOM (insertBefore_)
import qualified GHCJS.DOM.Node as Node
import qualified GHCJS.DOM.NodeList as NodeList
import GHCJS.DOM.Types
       (liftJSM, askJSM, runJSM, JSM, MonadJSM,
        FocusEvent, IsElement, IsEvent, IsNode, KeyboardEvent, Node,
        ToDOMString, TouchEvent, WheelEvent, uncheckedCastTo, ClipboardEvent)
import qualified GHCJS.DOM.Types as DOM
import GHCJS.DOM.UIEvent
import GHCJS.DOM.KeyboardEvent as KeyboardEvent
import qualified GHCJS.DOM.Window as Window
import Language.Javascript.JSaddle (call, eval, jsg, js1)
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.FastMutableIntMap (PatchIntMap (..))
import qualified Data.FastMutableIntMap as FastMutableIntMap
import System.IO.Unsafe (unsafePerformIO)

import Reflex.Requester.Base
import Reflex.Requester.Class
import Foreign.JavaScript.Internal.Utils

#ifndef ghcjs_HOST_OS
import GHCJS.DOM.Types (MonadJSM (..))

instance MonadJSM m => MonadJSM (HydrationDomBuilderT t m) where
    liftJSM' = HydrationDomBuilderT . liftJSM'
#endif

data HydrationDomSpace

data HydrationEventSpec (er :: EventTag -> *) = HydrationEventSpec deriving (Generic)

instance Default (HydrationEventSpec er)

instance DomSpace HydrationDomSpace where
  type EventSpec HydrationDomSpace = GhcjsEventSpec
  type RawDocument HydrationDomSpace = DOM.Document
  type RawTextNode HydrationDomSpace = ()
  type RawCommentNode HydrationDomSpace = ()
  type RawElement HydrationDomSpace = ()
  type RawFile HydrationDomSpace = DOM.File
  type RawInputElement HydrationDomSpace = ()
  type RawTextAreaElement HydrationDomSpace = ()
  type RawSelectElement HydrationDomSpace = ()
  addEventSpecFlags _ en f es = es
    { _ghcjsEventSpec_filters =
        let f' = Just . GhcjsEventFilter . \case
              Nothing -> \evt -> do
                mEventResult <- unGhcjsEventHandler (_ghcjsEventSpec_handler es) (en, evt)
                return (f mEventResult, return mEventResult)
              Just (GhcjsEventFilter oldFilter) -> \evt -> do
                (oldFlags, oldContinuation) <- oldFilter evt
                mEventResult <- oldContinuation
                let newFlags = oldFlags <> f mEventResult
                return (newFlags, return mEventResult)
        in DMap.alter f' en $ _ghcjsEventSpec_filters es
    }
--  addEventSpecFlags _ _ _ _ = HydrationEventSpec

{- Hydration:
    - Fence off `prerender` and totally replace immediately
    - Fence off `runWithReplace` and hydrate at postBuild
    - Otherwise hydrate at build time, skipping elements without SSR attribute, stripping the attrs as we go
-}

data HydrationDomBuilderEnv t m
   = HydrationDomBuilderEnv { _hydrationDomBuilderEnv_document :: {-# UNPACK #-} !Document
                            , _hydrationDomBuilderEnv_parent :: {-# UNPACK #-} !Node
                            , _hydrationDomBuilderEnv_unreadyChildren :: {-# UNPACK #-} !(IORef Word) -- Number of children who still aren't fully rendered
                            , _hydrationDomBuilderEnv_commitAction :: !(JSM ()) -- Action to take when all children are ready --TODO: we should probably get rid of this once we invoke it
                            , _hydrationDomBuilderEnv_hydrationMode :: {-# UNPACK #-} !(IORef HydrationMode) -- In hydration mode?
                            , _hydrationDomBuilderEnv_prerenderDepth :: {-# UNPACK #-} !(IORef Word)
                            , _hydrationDomBuilderEnv_eventChan :: {-# UNPACK #-} !(Chan [DSum (EventTriggerRef t) TriggerInvocation])
                            }

data HydrationState t m = HydrationState
  { _hydrationState_actions :: [Behavior t (m ())]
  , _hydrationState_previousNode :: {-# UNPACK #-} !(Maybe Node)
  }

addAction :: Monad m => Behavior t (m ()) -> HydrationDomBuilderT t m ()
addAction a = HydrationDomBuilderT $ modify $ \(HydrationState as n) -> HydrationState (a : as) n

newtype HydrationDomBuilderT t m a = HydrationDomBuilderT { unHydrationDomBuilderT :: ReaderT (HydrationDomBuilderEnv t m) (StateT (HydrationState t m) (RequesterT t JSM Identity (TriggerEventT t m))) a }
  deriving (Functor, Applicative, Monad, MonadFix, MonadIO, MonadException
#if MIN_VERSION_base(4,9,1)
           , MonadAsyncException
#endif
           )

instance PrimMonad m => PrimMonad (HydrationDomBuilderT x m) where
  type PrimState (HydrationDomBuilderT x m) = PrimState m
  primitive = lift . primitive

instance MonadTrans (HydrationDomBuilderT t) where
  lift = HydrationDomBuilderT . lift . lift . lift . lift

instance (Reflex t, MonadFix m) => DomRenderHook t (HydrationDomBuilderT t m) where
  withRenderHook hook (HydrationDomBuilderT a) = do
    e <- HydrationDomBuilderT ask
    s <- HydrationDomBuilderT get
    (a, s') <- HydrationDomBuilderT $ lift $ lift $ withRequesting $ \rsp -> do
      (x, req) <- lift $ runRequesterT (runStateT (runReaderT a e) s) $ runIdentity <$> rsp
      return (ffor req $ \rm -> hook $ traverseRequesterData (\r -> Identity <$> r) rm, x)
    HydrationDomBuilderT $ put s'
    pure a
  requestDomAction = HydrationDomBuilderT . lift . requestingIdentity
  requestDomAction_ = HydrationDomBuilderT . lift . requesting_

{-# INLINABLE runHydrationDomBuilderT #-}
runHydrationDomBuilderT
  :: ( MonadFix m
     , PerformEvent t m
     , MonadReflexCreateTrigger t m
     , MonadJSM m
     , MonadJSM (Performable m)
     , MonadRef m
     , Ref m ~ IORef
     )
  => HydrationDomBuilderT t m a
  -> HydrationDomBuilderEnv t m
  -> Maybe Node
  -> m (a, [Behavior t (m ())])
runHydrationDomBuilderT (HydrationDomBuilderT a) env prev = do
  (a, hs) <- flip runTriggerEventT (_hydrationDomBuilderEnv_eventChan env) $ do
    rec (result, req) <- runRequesterT (runStateT (runReaderT a env) (HydrationState [] prev)) rsp
        rsp <- performEventAsync $ ffor req $ \rm f -> liftJSM $ runInAnimationFrame f $
          traverseRequesterData (\r -> Identity <$> r) rm
    return result
  return (a, _hydrationState_actions hs)
  where
    runInAnimationFrame f x = void . DOM.inAnimationFrame' $ \_ -> do
        v <- synchronously x
        void . liftIO $ f v

instance Monad m => HasDocument (HydrationDomBuilderT t m) where
  {-# INLINABLE askDocument #-}
  askDocument = HydrationDomBuilderT $ asks _hydrationDomBuilderEnv_document

{-# INLINABLE askParent #-}
askParent :: Monad m => HydrationDomBuilderT t m Node
askParent = HydrationDomBuilderT $ asks _hydrationDomBuilderEnv_parent

{-# INLINABLE askEvents #-}
askEvents :: Monad m => HydrationDomBuilderT t m (Chan [DSum (EventTriggerRef t) TriggerInvocation])
askEvents = HydrationDomBuilderT . lift . lift . lift $ TriggerEventT.askEvents

localEnv :: Monad m => (HydrationState t m -> HydrationState t m) -> (HydrationDomBuilderEnv t m -> HydrationDomBuilderEnv t m) -> HydrationDomBuilderT t m a -> HydrationDomBuilderT t m a
localEnv f g (HydrationDomBuilderT m) = HydrationDomBuilderT $ do
  env <- ask
  hs <- get
  lift $ lift $ evalStateT (runReaderT m $ g env) (f hs)

{-# INLINABLE getPreviousNode #-}
getPreviousNode :: Monad m => HydrationDomBuilderT t m (Maybe DOM.Node)
getPreviousNode = HydrationDomBuilderT $ gets _hydrationState_previousNode

{-# INLINABLE setPreviousNode #-}
setPreviousNode :: Monad m => Maybe DOM.Node -> HydrationDomBuilderT t m ()
setPreviousNode n = HydrationDomBuilderT $ modify $ \hs -> hs { _hydrationState_previousNode = n }

{-# INLINABLE append #-}
append :: MonadJSM m => DOM.Node -> HydrationDomBuilderT t m ()
append n = do
  p <- askParent
  liftJSM $ appendChild_ p n
  return ()

data HydrationMode
  = HydrationMode_Hydrating
  | HydrationMode_Immediate
  deriving (Eq, Ord, Show)

getHydrationMode :: MonadIO m => HydrationDomBuilderT t m HydrationMode
getHydrationMode = do
  ref <- HydrationDomBuilderT $ asks _hydrationDomBuilderEnv_hydrationMode
  liftIO $ readIORef ref

{-# INLINABLE textNodeInternal #-}
textNodeInternal :: (MonadJSM m, ToDOMString contents) => contents -> HydrationDomBuilderT t m DOM.Text
textNodeInternal !t = makeNodeInternal (const $ pure True) (askDocument >>= \doc -> liftJSM $ createTextNode doc t) DOM.Text

{-# INLINABLE commentNodeInternal #-}
commentNodeInternal :: (MonadJSM m, ToDOMString contents) => contents -> HydrationDomBuilderT t m DOM.Comment
commentNodeInternal !t = makeNodeInternal (const $ pure True) (askDocument >>= \doc -> liftJSM $ createComment doc t) DOM.Comment

{-# INLINABLE makeNodeInternal #-}
makeNodeInternal :: (MonadJSM m, IsNode node, Typeable node) => (node -> HydrationDomBuilderT t m Bool) -> HydrationDomBuilderT t m node -> (DOM.JSVal -> node) -> HydrationDomBuilderT t m node
makeNodeInternal check mkNode constructor = do
  doc <- askDocument
  parent <- askParent
  liftIO $ putStr $ show (typeRep constructor) <> ": "
  getHydrationMode >>= \case
    HydrationMode_Immediate -> do
      liftIO $ putStrLn $ "Not in hydration mode, creating node"
      n <- mkNode
      append $ toNode n
      return n
    HydrationMode_Hydrating -> do
      lastHydrationNode <- getPreviousNode
      let go mLastNode = do
            node <- maybe (Node.getFirstChildUnchecked parent) Node.getNextSiblingUnchecked mLastNode
            DOM.castTo constructor node >>= \case
              Nothing -> do
                liftIO $ putStrLn $ "Wrong node type, skipping"
                go (Just node)
              Just tn -> check tn >>= \case
                True -> do
                  liftIO $ putStrLn $ "Using existing node"
                  return tn
                False -> do
                  liftIO $ putStrLn $ "Node failed check, skipping"
                  go (Just node)
      n <- go lastHydrationNode
      setPreviousNode $ Just $ toNode n
      return n

--  skipToCommentId "prerender-start" (liftJSM $ createComment doc "rerender-start") $ \new -> \case
--    Nothing -> void $ append $ toNode new
--    Just node -> void $ liftJSM $ Node.replaceChild parent new node

-- | s and e must both be children of the same node and s must precede e;
--   all nodes between s and e will be removed, but s and e will not be removed
deleteBetweenExclusive :: (MonadJSM m, IsNode start, IsNode end) => start -> end -> m ()
deleteBetweenExclusive s e = liftJSM $ do
  df <- createDocumentFragment =<< getOwnerDocumentUnchecked s
  extractBetweenExclusive df s e -- In many places in HydrationDomBuilderT, we assume that things always have a parent; by adding them to this DocumentFragment, we maintain that invariant

-- | s and e must both be children of the same node and s must precede e; all
--   nodes between s and e will be moved into the given DocumentFragment, but s
--   and e will not be moved
extractBetweenExclusive :: (MonadJSM m, IsNode start, IsNode end) => DOM.DocumentFragment -> start -> end -> m ()
extractBetweenExclusive df s e = liftJSM $ do
  f <- eval ("(function(df,s,e) { var x; for(;;) { x = s['nextSibling']; if(e===x) { break; }; df['appendChild'](x); } })" :: Text)
  void $ call f f (df, s, e)

-- | s and e must both be children of the same node and s must precede e;
--   s and all nodes between s and e will be removed, but e will not be removed
{-# INLINABLE deleteUpTo #-}
deleteUpTo :: (MonadJSM m, IsNode start, IsNode end) => start -> end -> m ()
deleteUpTo s e = do
  df <- createDocumentFragment =<< getOwnerDocumentUnchecked s
  extractUpTo df s e -- In many places in HydrationDomBuilderT, we assume that things always have a parent; by adding them to this DocumentFragment, we maintain that invariant

extractUpTo :: (MonadJSM m, IsNode start, IsNode end) => DOM.DocumentFragment -> start -> end -> m ()
#ifdef ghcjs_HOST_OS
--NOTE: Although wrapping this javascript in a function seems unnecessary, GHCJS's optimizer will break it if it is entered without that wrapping (as of 2017-09-04)
foreign import javascript unsafe
  "(function() { var x = $2; while(x !== $3) { var y = x['nextSibling']; $1['appendChild'](x); x = y; } })()"
  extractUpTo_ :: DOM.DocumentFragment -> DOM.Node -> DOM.Node -> IO ()
extractUpTo df s e = liftJSM $ extractUpTo_ df (toNode s) (toNode e)
#else
extractUpTo df s e = liftJSM $ do
  f <- eval ("(function(df,s,e){ var x = s; var y; for(;;) { y = x['nextSibling']; df['appendChild'](x); if(e===y) { break; } x = y; } })" :: Text)
  void $ call f f (df, s, e)
#endif

type SupportsHydrationDomBuilder t m = (Reflex t, MonadJSM m, MonadHold t m, MonadFix m, MonadReflexCreateTrigger t m, MonadRef m, Ref m ~ Ref JSM, Adjustable t m, PrimMonad m, PerformEvent t m, MonadJSM (Performable m))

{-# INLINABLE collectUpTo #-}
collectUpTo :: (MonadJSM m, IsNode start, IsNode end) => start -> end -> m DOM.DocumentFragment
collectUpTo s e = do
  currentParent <- getParentNodeUnchecked e -- May be different than it was at initial construction, e.g., because the parent may have dumped us in from a DocumentFragment
  collectUpToGivenParent currentParent s e

{-# INLINABLE collectUpToGivenParent #-}
collectUpToGivenParent :: (MonadJSM m, IsNode parent, IsNode start, IsNode end) => parent -> start -> end -> m DOM.DocumentFragment
collectUpToGivenParent currentParent s e = do
  doc <- getOwnerDocumentUnchecked currentParent
  df <- createDocumentFragment doc
  extractUpTo df s e
  return df

{-# INLINABLE wrap #-}
wrap
  :: forall m er t. (Reflex t, MonadJSM m, MonadReflexCreateTrigger t m, DomRenderHook t m)
  => Chan [DSum (EventTriggerRef t) TriggerInvocation]
  -> RawElement GhcjsDomSpace
  -> RawElementConfig er t HydrationDomSpace
--  -> m (Event t (DMap (WrapArg er EventName) Identity))
  -> m (EventSelector t (WrapArg er EventName))
wrap events e cfg = do
  liftIO $ putStrLn $ "called wrap"
  forM_ (_rawElementConfig_modifyAttributes cfg) $ \modifyAttrs -> requestDomAction_ $ ffor modifyAttrs $ imapM_ $ \(AttributeName mAttrNamespace n) mv -> case mAttrNamespace of
    Nothing -> maybe (removeAttribute e n) (setAttribute e n) mv
    Just ns -> maybe (removeAttributeNS e (Just ns) n) (setAttributeNS e (Just ns) n) mv
  eventTriggerRefs :: DMap EventName (EventFilterTriggerRef t er) <- liftJSM $ fmap DMap.fromList $ forM (DMap.toList $ _ghcjsEventSpec_filters $ _rawElementConfig_eventSpec cfg) $ \(en :=> GhcjsEventFilter f) -> do
    triggerRef <- liftIO $ newIORef Nothing
    _ <- elementOnEventName en e $ do --TODO: Something safer than this cast
      evt <- DOM.event
      (flags, k) <- liftJSM $ f $ GhcjsDomEvent evt
      when (_eventFlags_preventDefault flags) $ withIsEvent en DOM.preventDefault
      case _eventFlags_propagation flags of
        Propagation_Continue -> return ()
        Propagation_Stop -> withIsEvent en DOM.stopPropagation
        Propagation_StopImmediate -> withIsEvent en DOM.stopImmediatePropagation
      mv <- liftJSM k --TODO: Only do this when the event is subscribed
      liftIO $ forM_ mv $ \v -> writeChan events [EventTriggerRef triggerRef :=> TriggerInvocation v (return ())]
    return $ en :=> EventFilterTriggerRef triggerRef
  es <- do
    let h :: GhcjsEventHandler er
        !h = _ghcjsEventSpec_handler $ _rawElementConfig_eventSpec cfg -- Note: this needs to be done strictly and outside of the newFanEventWithTrigger, so that the newFanEventWithTrigger doesn't retain the entire cfg, which can cause a cyclic dependency that the GC won't be able to clean up
    ctx <- askJSM

    newFanEventWithTrigger $ \(WrapArg en) t ->
      case DMap.lookup en eventTriggerRefs of
        Just (EventFilterTriggerRef r) -> do
          writeIORef r $ Just t
          return $ do
            writeIORef r Nothing
        Nothing -> (`runJSM` ctx) <$> (`runJSM` ctx) (elementOnEventName en e $ do
          evt <- DOM.event
          mv <- lift $ unGhcjsEventHandler h (en, GhcjsDomEvent evt)
          case mv of
            Nothing -> return ()
            Just v -> liftIO $ do
              --TODO: I don't think this is quite right: if a new trigger is created between when this is enqueued and when it fires, this may not work quite right
              ref <- newIORef $ Just t
              writeChan events [EventTriggerRef ref :=> TriggerInvocation v (return ())])

  return es

{-# INLINABLE makeElement #-}
makeElement :: forall er t m a. (MonadJSM m, MonadHold t m, MonadFix m, MonadReflexCreateTrigger t m, Adjustable t m, Ref m ~ IORef, PerformEvent t m, MonadJSM (Performable m), MonadRef m) => Text -> ElementConfig er t HydrationDomSpace -> HydrationDomBuilderT t m a -> HydrationDomBuilderT t m ((Element er HydrationDomSpace t, a), DOM.Element)
makeElement elementTag cfg child = do
  doc <- askDocument
  let buildElement = do
        e <- uncheckedCastTo DOM.Element <$> case cfg ^. namespace of
          Nothing -> createElement doc elementTag
          Just ens -> createElementNS doc (Just ens) elementTag
        iforM_ (cfg ^. initialAttributes) $ \(AttributeName mAttrNamespace n) v -> case mAttrNamespace of
          Nothing -> setAttribute e n v
          Just ans -> setAttributeNS e (Just ans) n v
        pure e
      ssrAttr = "ssr" :: DOM.JSString
      hasSSRAttribute e = case cfg ^. namespace of
        Nothing -> hasAttribute e ssrAttr -- TODO: disabled for debugging <* removeAttribute e ssrAttr
        Just ns -> hasAttributeNS e (Just ns) ssrAttr -- TODO: disabled for debugging <* removeAttributeNS e (Just ns) ssrAttr
  -- TODO: prerender needs completely replacing
  e <- makeNodeInternal hasSSRAttribute buildElement DOM.Element
  -- Run the child builder with updated parent and previous sibling references
  result <- localEnv (\hs -> hs { _hydrationState_previousNode = Nothing }) (\env -> env { _hydrationDomBuilderEnv_parent = toNode e }) child
  events <- askEvents
  env <- HydrationDomBuilderT ask
  (ese, fire) <- newTriggerEvent
  addAction $ pure $ void $ runHydrationDomBuilderT (liftIO . fire <=< wrap events e $ extractRawElementConfig cfg) env Nothing
  collapsed <- switchHold never $ ffor ese $ \es -> DMap.singleton (WrapArg Click) . Identity <$> (select es (WrapArg Click)) -- TODO! this can't stay here, obviously.
  let evts = fan collapsed
  return ((Element evts (), result), e)

instance SupportsHydrationDomBuilder t m => NotReady t (HydrationDomBuilderT t m) where
  notReadyUntil e = do
    eOnce <- headE e
    env <- HydrationDomBuilderT ask
    let unreadyChildren = _hydrationDomBuilderEnv_unreadyChildren env
    liftIO $ modifyIORef' unreadyChildren succ
    let ready = do
          old <- liftIO $ readIORef unreadyChildren
          let new = pred old
          liftIO $ writeIORef unreadyChildren $! new
          when (new == 0) $ _hydrationDomBuilderEnv_commitAction env
    requestDomAction_ $ ready <$ eOnce
  notReady = do
    env <- HydrationDomBuilderT ask
    let unreadyChildren = _hydrationDomBuilderEnv_unreadyChildren env
    liftIO $ modifyIORef' unreadyChildren succ

instance SupportsHydrationDomBuilder t m => DomBuilder t (HydrationDomBuilderT t m) where
  type DomBuilderSpace (HydrationDomBuilderT t m) = HydrationDomSpace
  {-# INLINABLE textNode #-}
  textNode (TextNodeConfig initialContents mSetContents) = do
    n <- textNodeInternal initialContents
    mapM_ (requestDomAction_ . fmap (setNodeValue n . Just)) mSetContents
    return $ TextNode ()
  {-# INLINABLE commentNode #-}
  commentNode (CommentNodeConfig initialContents mSetContents) = do
    n <- commentNodeInternal initialContents
    mapM_ (requestDomAction_ . fmap (setNodeValue n . Just)) mSetContents
    return $ CommentNode ()
  {-# INLINABLE element #-}
  element elementTag cfg child = fst <$> makeElement elementTag cfg child
  {-# INLINABLE inputElement #-}
  inputElement cfg = do
    ((e, _), domElement) <- makeElement "input" (cfg ^. inputElementConfig_elementConfig) $ return ()
    let domInputElement = uncheckedCastTo DOM.HTMLInputElement domElement
    Input.setValue domInputElement $ cfg ^. inputElementConfig_initialValue
    v0 <- Input.getValue domInputElement
    let getMyValue = Input.getValue domInputElement
    valueChangedByUI <- requestDomAction $ liftJSM getMyValue <$ Reflex.select (_element_events e) (WrapArg Input)
    valueChangedBySetValue <- case _inputElementConfig_setValue cfg of
      Nothing -> return never
      Just eSetValue -> requestDomAction $ ffor eSetValue $ \v' -> do
        Input.setValue domInputElement v'
        getMyValue -- We get the value after setting it in case the browser has mucked with it somehow
    v <- holdDyn v0 $ leftmost
      [ valueChangedBySetValue
      , valueChangedByUI
      ]
    Input.setChecked domInputElement $ _inputElementConfig_initialChecked cfg
    checkedChangedByUI <- wrapDomEvent domInputElement (`on` Events.click) $ do
      Input.getChecked domInputElement
    checkedChangedBySetChecked <- case _inputElementConfig_setChecked cfg of
      Nothing -> return never
      Just eNewchecked -> requestDomAction $ ffor eNewchecked $ \newChecked -> do
        oldChecked <- Input.getChecked domInputElement
        Input.setChecked domInputElement newChecked
        return $ if newChecked /= oldChecked
                    then Just newChecked
                    else Nothing
    c <- holdDyn (_inputElementConfig_initialChecked cfg) $ leftmost
      [ fmapMaybe id checkedChangedBySetChecked
      , checkedChangedByUI
      ]
    let initialFocus = False --TODO: Is this correct?
    hasFocus <- holdDyn initialFocus $ leftmost
      [ False <$ Reflex.select (_element_events e) (WrapArg Blur)
      , True <$ Reflex.select (_element_events e) (WrapArg Focus)
      ]
    files <- holdDyn mempty <=< wrapDomEvent domInputElement (`on` Events.change) $ do
      mfiles <- Input.getFiles domInputElement
      let getMyFiles xs = fmap catMaybes . mapM (FileList.item xs) . flip take [0..] . fromIntegral =<< FileList.getLength xs
      maybe (return []) getMyFiles mfiles
    checked <- holdUniqDyn c
    return $ InputElement
      { _inputElement_value = v
      , _inputElement_checked = checked
      , _inputElement_checkedChange =  checkedChangedByUI
      , _inputElement_input = valueChangedByUI
      , _inputElement_hasFocus = hasFocus
      , _inputElement_element = e
      , _inputElement_raw = ()--domInputElement
      , _inputElement_files = files
      }
  {-# INLINABLE textAreaElement #-}
  textAreaElement cfg = do --TODO
    ((e, _), domElement) <- makeElement "textarea" (cfg ^. textAreaElementConfig_elementConfig) $ return ()
    let domTextAreaElement = uncheckedCastTo DOM.HTMLTextAreaElement domElement
    TextArea.setValue domTextAreaElement $ cfg ^. textAreaElementConfig_initialValue
    v0 <- TextArea.getValue domTextAreaElement
    let getMyValue = TextArea.getValue domTextAreaElement
    valueChangedByUI <- requestDomAction $ liftJSM getMyValue <$ Reflex.select (_element_events e) (WrapArg Input)
    valueChangedBySetValue <- case _textAreaElementConfig_setValue cfg of
      Nothing -> return never
      Just eSetValue -> requestDomAction $ ffor eSetValue $ \v' -> do
        TextArea.setValue domTextAreaElement v'
        getMyValue -- We get the value after setting it in case the browser has mucked with it somehow
    v <- holdDyn v0 $ leftmost
      [ valueChangedBySetValue
      , valueChangedByUI
      ]
    hasFocus <- mkHasFocus e
    return $ TextAreaElement
      { _textAreaElement_value = v
      , _textAreaElement_input = valueChangedByUI
      , _textAreaElement_hasFocus = hasFocus
      , _textAreaElement_element = e
      , _textAreaElement_raw = ()--domTextAreaElement
      }
  {-# INLINABLE selectElement #-}
  selectElement cfg child = do
    ((e, result), domElement) <- makeElement "select" (cfg ^. selectElementConfig_elementConfig) child
    let domSelectElement = uncheckedCastTo DOM.HTMLSelectElement domElement
    Select.setValue domSelectElement $ cfg ^. selectElementConfig_initialValue
    v0 <- Select.getValue domSelectElement
    let getMyValue = Select.getValue domSelectElement
    valueChangedByUI <- requestDomAction $ liftJSM getMyValue <$ Reflex.select (_element_events e) (WrapArg Change)
    valueChangedBySetValue <- case _selectElementConfig_setValue cfg of
      Nothing -> return never
      Just eSetValue -> requestDomAction $ ffor eSetValue $ \v' -> do
        Select.setValue domSelectElement v'
        getMyValue -- We get the value after setting it in case the browser has mucked with it somehow
    v <- holdDyn v0 $ leftmost
      [ valueChangedBySetValue
      , valueChangedByUI
      ]
    hasFocus <- mkHasFocus e
    let wrapped = SelectElement
          { _selectElement_value = v
          , _selectElement_change = valueChangedByUI
          , _selectElement_hasFocus = hasFocus
          , _selectElement_element = e
          , _selectElement_raw = ()--domSelectElement
          }
    return (wrapped, result)
  placeRawElement _ = return () -- append . toNode
  wrapRawElement () _ = return $ Element (EventSelector $ const never) ()

data FragmentState
  = FragmentState_Unmounted
  | FragmentState_Mounted (DOM.Text, DOM.Text)

data HydrationDomFragment = HydrationDomFragment
  { _hydrationDomFragment_document :: DOM.DocumentFragment
  , _hydrationDomFragment_state :: IORef FragmentState
  }

extractFragment :: MonadJSM m => HydrationDomFragment -> m ()
extractFragment fragment = do
  state <- liftIO $ readIORef $ _hydrationDomFragment_state fragment
  case state of
    FragmentState_Unmounted -> return ()
    FragmentState_Mounted (before, after) -> do
      extractBetweenExclusive (_hydrationDomFragment_document fragment) before after
      liftIO $ writeIORef (_hydrationDomFragment_state fragment) FragmentState_Unmounted

instance SupportsHydrationDomBuilder t m => MountableDomBuilder t (HydrationDomBuilderT t m) where
  type DomFragment (HydrationDomBuilderT t m) = HydrationDomFragment
  buildDomFragment w = do
    df <- createDocumentFragment =<< askDocument
    result <- localEnv id (\env -> env { _hydrationDomBuilderEnv_parent = toNode df }) w
    state <- liftIO $ newIORef FragmentState_Unmounted
    return (HydrationDomFragment df state, result)
  mountDomFragment fragment setFragment = do
    parent <- askParent
    extractFragment fragment
    before <- textNodeInternal ("" :: Text)
    appendChild_ parent $ _hydrationDomFragment_document fragment
    after <- textNodeInternal ("" :: Text)
    xs <- foldDyn (\new (previous, _) -> (new, Just previous)) (fragment, Nothing) setFragment
    requestDomAction_ $ ffor (updated xs) $ \(childFragment, Just previousFragment) -> do
      extractFragment previousFragment
      extractFragment childFragment
      insertBefore (_hydrationDomFragment_document childFragment) after
      liftIO $ writeIORef (_hydrationDomFragment_state childFragment) $ FragmentState_Mounted (before, after)
    liftIO $ writeIORef (_hydrationDomFragment_state fragment) $ FragmentState_Mounted (before, after)

skipToCommentId :: MonadJSM m => Text -> HydrationDomBuilderT t m (DOM.Node, Text)
skipToCommentId prefix = do
  doc <- askDocument
  parent <- askParent
  lastHydrationNode <- getPreviousNode
  let go mLastNode = do
        node <- maybe (Node.getFirstChildUnchecked parent) Node.getNextSiblingUnchecked mLastNode
        DOM.castTo DOM.Comment node >>= \case
          Just comment -> do
            commentText <- Node.getTextContentUnchecked comment
            case T.stripPrefix prefix commentText of
              Just key -> pure (comment, key)
              Nothing -> do
                liftIO $ putStrLn $ "Bad key in comment, skipping"
                go (Just node)
          Nothing -> do
            commentText <- Node.getTextContentUnchecked node
            liftIO $ putStrLn $ "Not a comment, skipping"
            liftIO $ putStrLn commentText
            go (Just node)
  (a, key) <- go lastHydrationNode
  setPreviousNode $ Just $ toNode a
  pure (toNode a, key)

skipToReplaceStart :: MonadJSM m => HydrationDomBuilderT t m (DOM.Node, Text)
skipToReplaceStart = skipToCommentId "replace-start"

skipToReplaceEnd :: MonadJSM m => Text -> HydrationDomBuilderT t m DOM.Node
skipToReplaceEnd key = fmap fst $ skipToCommentId $ "replace-end" <> key

instance (Reflex t, Adjustable t m, MonadJSM m, MonadHold t m, MonadFix m, PrimMonad m, Ref m ~ IORef, PerformEvent t m, MonadReflexCreateTrigger t m, MonadJSM (Performable m), MonadRef m) => Adjustable t (HydrationDomBuilderT t m) where
  {-# INLINABLE runWithReplace #-}
  runWithReplace a0 a' = do
    liftIO $ putStrLn "In runWithReplace"
    initialEnv <- HydrationDomBuilderT ask
    let hydrating = _hydrationDomBuilderEnv_hydrationMode initialEnv
    initialHydrationMode <- liftIO $ readIORef hydrating
    (before, beforeKey) <- case initialHydrationMode of
      HydrationMode_Hydrating -> skipToReplaceStart
      HydrationMode_Immediate -> do
        t <- textNodeInternal ("" :: Text)
        append $ toNode t
        pure (toNode t, "")
    let parentUnreadyChildren = _hydrationDomBuilderEnv_unreadyChildren initialEnv
    haveEverBeenReady <- liftIO $ newIORef False
    currentCohort <- liftIO $ newIORef (-1 :: Int) -- Equal to the cohort currently in the DOM
    let myCommitAction = do
          liftIO (readIORef haveEverBeenReady) >>= \case
            True -> return ()
            False -> do
              liftIO $ writeIORef haveEverBeenReady True
              old <- liftIO $ readIORef parentUnreadyChildren
              let new = pred old
              liftIO $ writeIORef parentUnreadyChildren $! new
              when (new == 0) $ _hydrationDomBuilderEnv_commitAction initialEnv
    -- We draw 'after' in this roundabout way to avoid using MonadFix
    doc <- askDocument
    parent <- askParent
    after <- case initialHydrationMode of
      HydrationMode_Hydrating -> skipToReplaceEnd beforeKey
      HydrationMode_Immediate -> do
        t <- textNodeInternal ("" :: Text)
        append $ toNode t
        pure (toNode t)
    let drawInitialChild = do
          liftIO $ putStrLn "drawInitialChild"
          p <- liftIO (readIORef hydrating) >>= \case
            HydrationMode_Hydrating -> pure parent
            HydrationMode_Immediate -> toNode <$> createDocumentFragment doc
          unreadyChildren <- liftIO $ newIORef 0
          (result, HydrationState h' _) <- flip runStateT (HydrationState [] Nothing) $ runReaderT (unHydrationDomBuilderT a0) initialEnv
            { _hydrationDomBuilderEnv_unreadyChildren = unreadyChildren
            , _hydrationDomBuilderEnv_commitAction = myCommitAction
            , _hydrationDomBuilderEnv_parent = p
            }
          liftIO $ readIORef unreadyChildren >>= \case
            0 -> writeIORef haveEverBeenReady True
            _ -> modifyIORef' parentUnreadyChildren succ
          liftIO $ putStrLn "drawInitialChild: end"
          return (h', result)
    a'' <- numberOccurrences a'
    (result0, evt) <- HydrationDomBuilderT $ lift $ lift $ runWithReplace drawInitialChild $ ffor a'' $ \(cohortId, child) -> do
      p <- liftIO (readIORef hydrating) >>= \case
        HydrationMode_Hydrating -> pure parent
        HydrationMode_Immediate -> toNode <$> createDocumentFragment doc
      unreadyChildren <- liftIO $ newIORef 0
      let commitAction = do
            liftIO $ putStrLn "Committing runWithReplace update"
            c <- liftIO $ readIORef currentCohort
            when (c <= cohortId) $ do -- If a newer cohort has already been committed, just ignore this
              deleteBetweenExclusive before after
              insertBefore p after
              liftIO $ writeIORef currentCohort cohortId
              myCommitAction
      (result, HydrationState h' _) <- flip runStateT (HydrationState [] $ Just $ toNode before) $ runReaderT (unHydrationDomBuilderT child) $ initialEnv
            { _hydrationDomBuilderEnv_unreadyChildren = unreadyChildren
            , _hydrationDomBuilderEnv_commitAction = commitAction
            , _hydrationDomBuilderEnv_parent = p
            }
      uc <- liftIO $ readIORef unreadyChildren
      h <- liftIO $ readIORef hydrating
      let commitActionToRunNow = if uc == 0
            then Just $ commitAction
            else Nothing -- A child will run it when unreadyChildren is decremented to 0
          actions = case h of
            HydrationMode_Hydrating -> Left h'
            HydrationMode_Immediate -> Right commitActionToRunNow
      return (actions, result)
    let (hydrationAction, commitAction) = fanEither $ fmap fst evt
        f :: [Behavior t (m ())] -> Behavior t (m ())
        f = fmap (void . sequence) . sequence
    addAction . join =<< hold (f $ fst result0) (fmap f hydrationAction)
    requestDomAction_ $ fmapMaybe id commitAction
    return (snd result0, fmap snd evt)

  {-# INLINABLE traverseIntMapWithKeyWithAdjust #-}
  traverseIntMapWithKeyWithAdjust = traverseIntMapWithKeyWithAdjust'
  {-# INLINABLE traverseDMapWithKeyWithAdjust #-}
  traverseDMapWithKeyWithAdjust = traverseDMapWithKeyWithAdjust'
  {-# INLINABLE traverseDMapWithKeyWithAdjustWithMove #-}
  traverseDMapWithKeyWithAdjustWithMove = do
    let updateChildUnreadiness (p :: PatchDMapWithMove k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v')) old = do
          let new :: forall a. k a -> PatchDMapWithMove.NodeInfo k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') a -> IO (PatchDMapWithMove.NodeInfo k (Constant (IORef (ChildReadyState k))) a)
              new k = PatchDMapWithMove.nodeInfoMapFromM $ \case
                PatchDMapWithMove.From_Insert (Compose (_, _, sRef, _)) -> do
                  readIORef sRef >>= \case
                    ChildReadyState_Ready -> return PatchDMapWithMove.From_Delete
                    ChildReadyState_Unready _ -> do
                      writeIORef sRef $ ChildReadyState_Unready $ Just $ Some.This k
                      return $ PatchDMapWithMove.From_Insert $ Constant sRef
                PatchDMapWithMove.From_Delete -> return PatchDMapWithMove.From_Delete
                PatchDMapWithMove.From_Move fromKey -> return $ PatchDMapWithMove.From_Move fromKey
              deleteOrMove :: forall a. k a -> Product (Constant (IORef (ChildReadyState k))) (ComposeMaybe k) a -> IO (Constant () a)
              deleteOrMove _ (Pair (Constant sRef) (ComposeMaybe mToKey)) = do
                writeIORef sRef $ ChildReadyState_Unready $ Some.This <$> mToKey -- This will be Nothing if deleting, and Just if moving, so it works out in both cases
                return $ Constant ()
          p' <- fmap unsafePatchDMapWithMove $ DMap.traverseWithKey new $ unPatchDMapWithMove p
          _ <- DMap.traverseWithKey deleteOrMove $ PatchDMapWithMove.getDeletionsAndMoves p old
          return $ applyAlways p' old
    hoistTraverseWithKeyWithAdjust traverseDMapWithKeyWithAdjustWithMove mapPatchDMapWithMove updateChildUnreadiness $ \placeholders lastPlaceholderRef (p_ :: PatchDMapWithMove k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v')) -> do
      let p = unPatchDMapWithMove p_
      phsBefore <- liftIO $ readIORef placeholders
      lastPlaceholder <- liftIO $ readIORef lastPlaceholderRef
      let collectIfMoved :: forall a. k a -> PatchDMapWithMove.NodeInfo k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') a -> JSM (Constant (Maybe DOM.DocumentFragment) a)
          collectIfMoved k e = do
            let mThisPlaceholder = Map.lookup (Some.This k) phsBefore -- Will be Nothing if this element wasn't present before
                nextPlaceholder = maybe lastPlaceholder snd $ Map.lookupGT (Some.This k) phsBefore
            case isJust $ getComposeMaybe $ PatchDMapWithMove._nodeInfo_to e of
              False -> do
                mapM_ (`deleteUpTo` nextPlaceholder) mThisPlaceholder
                return $ Constant Nothing
              True -> do
                Constant <$> mapM (`collectUpTo` nextPlaceholder) mThisPlaceholder
      collected <- DMap.traverseWithKey collectIfMoved p
      let !phsAfter = fromMaybe phsBefore $ apply (weakenPatchDMapWithMoveWith (\(Compose (_, ph, _, _)) -> ph) p_) phsBefore --TODO: Don't recompute this
      let placeFragment :: forall a. k a -> PatchDMapWithMove.NodeInfo k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') a -> JSM (Constant () a)
          placeFragment k e = do
            let nextPlaceholder = maybe lastPlaceholder snd $ Map.lookupGT (Some.This k) phsAfter
            case PatchDMapWithMove._nodeInfo_from e of
              PatchDMapWithMove.From_Insert (Compose (df, _, _, _)) -> do
                df `insertBefore` nextPlaceholder
              PatchDMapWithMove.From_Delete -> do
                return ()
              PatchDMapWithMove.From_Move fromKey -> do
                Just (Constant mdf) <- return $ DMap.lookup fromKey collected
                mapM_ (`insertBefore` nextPlaceholder) mdf
            return $ Constant ()
      mapM_ (\(k :=> v) -> void $ placeFragment k v) $ DMap.toDescList p -- We need to go in reverse order here, to make sure the placeholders are in the right spot at the right time
      liftIO $ writeIORef placeholders $! phsAfter

{-# INLINABLE traverseDMapWithKeyWithAdjust' #-}
traverseDMapWithKeyWithAdjust' :: forall t m (k :: * -> *) v v'. (Adjustable t m, MonadHold t m, MonadFix m, MonadIO m, MonadJSM m, PrimMonad m, DMap.GCompare k) => (forall a. k a -> v a -> HydrationDomBuilderT t m (v' a)) -> DMap k v -> Event t (PatchDMap k v) -> HydrationDomBuilderT t m (DMap k v', Event t (PatchDMap k v'))
traverseDMapWithKeyWithAdjust' = do
  let updateChildUnreadiness (p :: PatchDMap k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v')) old = do
        let new :: forall a. k a -> ComposeMaybe (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') a -> IO (ComposeMaybe (Constant (IORef (ChildReadyState k))) a)
            new k (ComposeMaybe m) = ComposeMaybe <$> case m of
              Nothing -> return Nothing
              Just (Compose (_, _, sRef, _)) -> do
                readIORef sRef >>= \case
                  ChildReadyState_Ready -> return Nothing -- Delete this child, since it's ready
                  ChildReadyState_Unready _ -> do
                    writeIORef sRef $ ChildReadyState_Unready $ Just $ Some.This k
                    return $ Just $ Constant sRef
            delete _ (Constant sRef) = do
              writeIORef sRef $ ChildReadyState_Unready Nothing
              return $ Constant ()
        p' <- fmap PatchDMap $ DMap.traverseWithKey new $ unPatchDMap p
        _ <- DMap.traverseWithKey delete $ PatchDMap.getDeletions p old
        return $ applyAlways p' old
  hoistTraverseWithKeyWithAdjust traverseDMapWithKeyWithAdjust mapPatchDMap updateChildUnreadiness $ \placeholders lastPlaceholderRef (PatchDMap p) -> do
    phs <- liftIO $ readIORef placeholders
    forM_ (DMap.toList p) $ \(k :=> ComposeMaybe mv) -> do
      lastPlaceholder <- liftIO $ readIORef lastPlaceholderRef
      let nextPlaceholder = maybe lastPlaceholder snd $ Map.lookupGT (Some.This k) phs
      forM_ (Map.lookup (Some.This k) phs) $ \thisPlaceholder -> thisPlaceholder `deleteUpTo` nextPlaceholder
      forM_ mv $ \(Compose (df, _, _, _)) -> df `insertBefore` nextPlaceholder
    liftIO $ writeIORef placeholders $! fromMaybe phs $ apply (weakenPatchDMapWith (\(Compose (_, ph, _, _)) -> ph) $ PatchDMap p) phs

{-# INLINABLE traverseIntMapWithKeyWithAdjust' #-}
traverseIntMapWithKeyWithAdjust' :: forall t m v v'. (Adjustable t m, MonadHold t m, MonadFix m, MonadIO m, MonadJSM m, PrimMonad m) => (IntMap.Key -> v -> HydrationDomBuilderT t m v') -> IntMap v -> Event t (PatchIntMap v) -> HydrationDomBuilderT t m (IntMap v', Event t (PatchIntMap v'))
traverseIntMapWithKeyWithAdjust' = do
  let updateChildUnreadiness (p@(PatchIntMap pInner) :: PatchIntMap (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v')) old = do
        let new :: IntMap.Key -> Maybe (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v') -> IO (Maybe (IORef ChildReadyStateInt))
            new k m = case m of
              Nothing -> return Nothing
              Just (_, _, sRef, _) -> do
                readIORef sRef >>= \case
                  ChildReadyStateInt_Ready -> return Nothing -- Delete this child, since it's ready
                  ChildReadyStateInt_Unready _ -> do
                    writeIORef sRef $ ChildReadyStateInt_Unready $ Just k
                    return $ Just sRef
            delete _ sRef = do
              writeIORef sRef $ ChildReadyStateInt_Unready Nothing
              return ()
        p' <- PatchIntMap <$> IntMap.traverseWithKey new pInner
        _ <- IntMap.traverseWithKey delete $ FastMutableIntMap.getDeletions p old
        return $ applyAlways p' old
  hoistTraverseIntMapWithKeyWithAdjust traverseIntMapWithKeyWithAdjust updateChildUnreadiness $ \placeholders lastPlaceholderRef (PatchIntMap p) -> do
    phs <- liftIO $ readIORef placeholders
    forM_ (IntMap.toList p) $ \(k, mv) -> do
      lastPlaceholder <- liftIO $ readIORef lastPlaceholderRef
      let nextPlaceholder = maybe lastPlaceholder snd $ IntMap.lookupGT k phs
      forM_ (IntMap.lookup k phs) $ \thisPlaceholder -> thisPlaceholder `deleteUpTo` nextPlaceholder
      forM_ mv $ \(df, _, _, _) -> df `insertBefore` nextPlaceholder
    liftIO $ writeIORef placeholders $! fromMaybe phs $ apply ((\(_, ph, _, _) -> ph) <$> PatchIntMap p) phs

{-# INLINE hoistTraverseIntMapWithKeyWithAdjust #-}
hoistTraverseIntMapWithKeyWithAdjust :: forall v v' t m p.
  ( Adjustable t m
  , MonadIO m
  , MonadJSM m
  , MonadFix m
  , PrimMonad m
  , Monoid (p (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v'))
  , Functor p
  )
  => (   (IntMap.Key -> v -> RequesterT t JSM Identity (TriggerEventT t m) (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v'))
      -> IntMap v
      -> Event t (p v)
      -> RequesterT t JSM Identity (TriggerEventT t m) (IntMap (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v'), Event t (p (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v')))
     ) -- ^ The base monad's traversal
  -> (p (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v') -> IntMap (IORef ChildReadyStateInt) -> IO (IntMap (IORef ChildReadyStateInt))) -- ^ Given a patch for the children DOM elements, produce a patch for the childrens' unreadiness state
  -> (IORef (IntMap DOM.Text) -> IORef DOM.Text -> p (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v') -> JSM ()) -- ^ Apply a patch to the DOM
  -> (IntMap.Key -> v -> HydrationDomBuilderT t m v')
  -> IntMap v
  -> Event t (p v)
  -> HydrationDomBuilderT t m (IntMap v', Event t (p v'))
hoistTraverseIntMapWithKeyWithAdjust base updateChildUnreadiness applyDomUpdate_ f dm0 dm' = do
  initialEnv <- HydrationDomBuilderT ask
  let parentUnreadyChildren = _hydrationDomBuilderEnv_unreadyChildren initialEnv
  pendingChange :: IORef (IntMap (IORef ChildReadyStateInt), p (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v')) <- liftIO $ newIORef mempty
  haveEverBeenReady <- liftIO $ newIORef False
  placeholders <- liftIO $ newIORef $ error "placeholders not yet initialized"
  lastPlaceholderRef <- liftIO $ newIORef $ error "lastPlaceholderRef not yet initialized"
  let applyDomUpdate p = do
        applyDomUpdate_ placeholders lastPlaceholderRef p
        markSelfReady
        liftIO $ writeIORef pendingChange $! mempty
      markSelfReady = do
        liftIO (readIORef haveEverBeenReady) >>= \case
          True -> return ()
          False -> do
            liftIO $ writeIORef haveEverBeenReady True
            old <- liftIO $ readIORef parentUnreadyChildren
            let new = pred old
            liftIO $ writeIORef parentUnreadyChildren $! new
            when (new == 0) $ _hydrationDomBuilderEnv_commitAction initialEnv
      markChildReady :: IORef ChildReadyStateInt -> JSM ()
      markChildReady childReadyState = do
        liftIO (readIORef childReadyState) >>= \case
          ChildReadyStateInt_Ready -> return ()
          ChildReadyStateInt_Unready countedAt -> do
            liftIO $ writeIORef childReadyState ChildReadyStateInt_Ready
            case countedAt of
              Nothing -> return ()
              Just k -> do -- This child has been counted as unready, so we need to remove it from the unready set
                (oldUnready, p) <- liftIO $ readIORef pendingChange
                when (not $ IntMap.null oldUnready) $ do -- This shouldn't actually ever be null
                  let newUnready = IntMap.delete k oldUnready
                  liftIO $ writeIORef pendingChange (newUnready, p)
                  when (IntMap.null newUnready) $ do
                    applyDomUpdate p
  (children0, children') <- HydrationDomBuilderT $ lift $ lift $ base (\k v -> drawChildUpdateInt initialEnv markChildReady $ f k v) dm0 dm'
  let processChild k (_, _, sRef, _) = do
        readIORef sRef >>= \case
          ChildReadyStateInt_Ready -> return Nothing
          ChildReadyStateInt_Unready _ -> do
            writeIORef sRef $ ChildReadyStateInt_Unready $ Just k
            return $ Just sRef
  initialUnready <- liftIO $ IntMap.mapMaybe id <$> IntMap.traverseWithKey processChild children0
  liftIO $ if IntMap.null initialUnready
    then writeIORef haveEverBeenReady True
    else do
      modifyIORef' parentUnreadyChildren succ
      writeIORef pendingChange (initialUnready, mempty) -- The patch is always empty because it got applied implicitly when we ran the children the first time
  let result0 = IntMap.map (\(_, _, _, v) -> v) children0
      placeholders0 = fmap (\(_, ph, _, _) -> ph) children0
      result' = ffor children' $ fmap $ \(_, _, _, r) -> r
  liftIO $ writeIORef placeholders $! placeholders0
  _ <- IntMap.traverseWithKey (\_ (df, _, _, _) -> void $ append $ toNode df) children0
  liftIO . writeIORef lastPlaceholderRef =<< textNodeInternal ("" :: Text)
  requestDomAction_ $ ffor children' $ \p -> do
    (oldUnready, oldP) <- liftIO $ readIORef pendingChange
    newUnready <- liftIO $ updateChildUnreadiness p oldUnready
    let !newP = p <> oldP
    liftIO $ writeIORef pendingChange (newUnready, newP)
    when (IntMap.null newUnready) $ do
      applyDomUpdate newP
  return (result0, result')

{-# INLINABLE hoistTraverseWithKeyWithAdjust #-}
hoistTraverseWithKeyWithAdjust :: forall (k :: * -> *) v v' t m p.
  ( Adjustable t m
  , MonadHold t m
  , DMap.GCompare k
  , MonadIO m
  , MonadJSM m
  , PrimMonad m
  , MonadFix m
  , Patch (p k v)
  , PatchTarget (p k (Constant Int)) ~ DMap k (Constant Int)
  , Monoid (p k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v'))
  , Patch (p k (Constant Int))
  )
  => (forall vv vv'.
         (forall a. k a -> vv a -> RequesterT t JSM Identity (TriggerEventT t m) (vv' a))
      -> DMap k vv
      -> Event t (p k vv)
      -> RequesterT t JSM Identity (TriggerEventT t m) (DMap k vv', Event t (p k vv'))
     ) -- ^ The base monad's traversal
  -> (forall vv vv'. (forall a. vv a -> vv' a) -> p k vv -> p k vv') -- ^ A way of mapping over the patch type
  -> (p k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') -> DMap k (Constant (IORef (ChildReadyState k))) -> IO (DMap k (Constant (IORef (ChildReadyState k))))) -- ^ Given a patch for the children DOM elements, produce a patch for the childrens' unreadiness state
  -> (IORef (Map.Map (Some.Some k) DOM.Text) -> IORef DOM.Text -> p k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v') -> JSM ()) -- ^ Apply a patch to the DOM
  -> (forall a. k a -> v a -> HydrationDomBuilderT t m (v' a))
  -> DMap k v
  -> Event t (p k v)
  -> HydrationDomBuilderT t m (DMap k v', Event t (p k v'))
hoistTraverseWithKeyWithAdjust base mapPatch updateChildUnreadiness applyDomUpdate_ (f :: forall a. k a -> v a -> HydrationDomBuilderT t m (v' a)) (dm0 :: DMap k v) dm' = do
  initialEnv <- HydrationDomBuilderT ask
  let parentUnreadyChildren = _hydrationDomBuilderEnv_unreadyChildren initialEnv
  pendingChange :: IORef (DMap k (Constant (IORef (ChildReadyState k))), p k (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v')) <- liftIO $ newIORef mempty
  haveEverBeenReady <- liftIO $ newIORef False
  placeholders <- liftIO $ newIORef $ error "placeholders not yet initialized"
  lastPlaceholderRef <- liftIO $ newIORef $ error "lastPlaceholderRef not yet initialized"
  let applyDomUpdate p = do
        applyDomUpdate_ placeholders lastPlaceholderRef p
        markSelfReady
        liftIO $ writeIORef pendingChange $! mempty
      markSelfReady = do
        liftIO (readIORef haveEverBeenReady) >>= \case
          True -> return ()
          False -> do
            liftIO $ writeIORef haveEverBeenReady True
            old <- liftIO $ readIORef parentUnreadyChildren
            let new = pred old
            liftIO $ writeIORef parentUnreadyChildren $! new
            when (new == 0) $ _hydrationDomBuilderEnv_commitAction initialEnv
      markChildReady :: IORef (ChildReadyState k) -> JSM ()
      markChildReady childReadyState = do
        liftIO (readIORef childReadyState) >>= \case
          ChildReadyState_Ready -> return ()
          ChildReadyState_Unready countedAt -> do
            liftIO $ writeIORef childReadyState ChildReadyState_Ready
            case countedAt of
              Nothing -> return ()
              Just (Some.This k) -> do -- This child has been counted as unready, so we need to remove it from the unready set
                (oldUnready, p) <- liftIO $ readIORef pendingChange
                when (not $ DMap.null oldUnready) $ do -- This shouldn't actually ever be null
                  let newUnready = DMap.delete k oldUnready
                  liftIO $ writeIORef pendingChange (newUnready, p)
                  when (DMap.null newUnready) $ do
                    applyDomUpdate p
  (children0, children') <- HydrationDomBuilderT $ lift $ lift $ base (\k v -> drawChildUpdate initialEnv markChildReady $ f k v) dm0 dm'
  let processChild k (Compose (_, _, sRef, _)) = ComposeMaybe <$> do
        readIORef sRef >>= \case
          ChildReadyState_Ready -> return Nothing
          ChildReadyState_Unready _ -> do
            writeIORef sRef $ ChildReadyState_Unready $ Just $ Some.This k
            return $ Just $ Constant sRef
  initialUnready <- liftIO $ DMap.mapMaybeWithKey (\_ -> getComposeMaybe) <$> DMap.traverseWithKey processChild children0
  liftIO $ if DMap.null initialUnready
    then writeIORef haveEverBeenReady True
    else do
      modifyIORef' parentUnreadyChildren succ
      writeIORef pendingChange (initialUnready, mempty) -- The patch is always empty because it got applied implicitly when we ran the children the first time
  let result0 = DMap.map (\(Compose (_, _, _, v)) -> v) children0
      placeholders0 = weakenDMapWith (\(Compose (_, ph, _, _)) -> ph) children0
      result' = ffor children' $ mapPatch $ \(Compose (_, _, _, r)) -> r
  liftIO $ writeIORef placeholders $! placeholders0
  _ <- DMap.traverseWithKey (\_ (Compose (df, _, _, _)) -> Constant () <$ append (toNode df)) children0
  liftIO . writeIORef lastPlaceholderRef =<< textNodeInternal ("" :: Text)
  requestDomAction_ $ ffor children' $ \p -> do
    (oldUnready, oldP) <- liftIO $ readIORef pendingChange
    newUnready <- liftIO $ updateChildUnreadiness p oldUnready
    let !newP = p <> oldP
    liftIO $ writeIORef pendingChange (newUnready, newP)
    when (DMap.null newUnready) $ do
      applyDomUpdate newP
  return (result0, result')

{-# INLINABLE drawChildUpdate #-}
drawChildUpdate :: (MonadIO m, MonadJSM m)
  => HydrationDomBuilderEnv t m
  -> (IORef (ChildReadyState k) -> JSM ()) -- This will NOT be called if the child is ready at initialization time; instead, the ChildReadyState return value will be ChildReadyState_Ready
  -> HydrationDomBuilderT t m (v' a)
  -> RequesterT t JSM Identity (TriggerEventT t m) (Compose ((,,,) DOM.DocumentFragment DOM.Text (IORef (ChildReadyState k))) v' a)
drawChildUpdate initialEnv markReady child = do
  childReadyState <- liftIO $ newIORef $ ChildReadyState_Unready Nothing
  unreadyChildren <- liftIO $ newIORef 0
  df <- createDocumentFragment $ _hydrationDomBuilderEnv_document initialEnv
  (placeholder, result) <- flip evalStateT (HydrationState [] Nothing) $ runReaderT (unHydrationDomBuilderT $ (,) <$> textNodeInternal ("" :: Text) <*> child) $ initialEnv
    { _hydrationDomBuilderEnv_parent = toNode df
    , _hydrationDomBuilderEnv_unreadyChildren = unreadyChildren
    , _hydrationDomBuilderEnv_commitAction = markReady childReadyState
    }
  u <- liftIO $ readIORef unreadyChildren
  when (u == 0) $ liftIO $ writeIORef childReadyState ChildReadyState_Ready
  return $ Compose (df, placeholder, childReadyState, result)

{-# INLINABLE drawChildUpdateInt #-}
drawChildUpdateInt :: (MonadIO m, MonadJSM m)
  => HydrationDomBuilderEnv t m
  -> (IORef ChildReadyStateInt -> JSM ()) -- This will NOT be called if the child is ready at initialization time; instead, the ChildReadyState return value will be ChildReadyState_Ready
  -> HydrationDomBuilderT t m v'
  -> RequesterT t JSM Identity (TriggerEventT t m) (DOM.DocumentFragment, DOM.Text, IORef ChildReadyStateInt, v')
drawChildUpdateInt initialEnv markReady child = do
  childReadyState <- liftIO $ newIORef $ ChildReadyStateInt_Unready Nothing
  unreadyChildren <- liftIO $ newIORef 0
  df <- createDocumentFragment $ _hydrationDomBuilderEnv_document initialEnv
  (placeholder, result) <- flip evalStateT (HydrationState [] Nothing) $ runReaderT (unHydrationDomBuilderT $ (,) <$> textNodeInternal ("" :: Text) <*> child) $ initialEnv
    { _hydrationDomBuilderEnv_parent = toNode df
    , _hydrationDomBuilderEnv_unreadyChildren = unreadyChildren
    , _hydrationDomBuilderEnv_commitAction = markReady childReadyState
    }
  u <- liftIO $ readIORef unreadyChildren
  when (u == 0) $ liftIO $ writeIORef childReadyState ChildReadyStateInt_Ready
  return (df, placeholder, childReadyState, result)

mkHasFocus :: (MonadHold t m, Reflex t) => Element er d t -> m (Dynamic t Bool)
mkHasFocus e = do
  let initialFocus = False --TODO: Actually get the initial focus of the element
  holdDyn initialFocus $ leftmost
    [ False <$ Reflex.select (_element_events e) (WrapArg Blur)
    , True <$ Reflex.select (_element_events e) (WrapArg Focus)
    ]

insertAfter :: (MonadJSM m, IsNode new, IsNode existing) => new -> existing -> m ()
insertAfter new existing = do
  p <- getParentNodeUnchecked existing
  Node.getNextSibling existing >>= DOM.insertBefore_ p new

insertBefore :: (MonadJSM m, IsNode new, IsNode existing) => new -> existing -> m ()
insertBefore new existing = do
  p <- getParentNodeUnchecked existing
  DOM.insertBefore_ p new (Just existing) -- If there's no parent, that means we've been removed from the DOM; this should not happen if the we're removing ourselves from the performEvent properly

instance PerformEvent t m => PerformEvent t (HydrationDomBuilderT t m) where
  type Performable (HydrationDomBuilderT t m) = Performable m
  {-# INLINABLE performEvent_ #-}
  performEvent_ e = lift $ performEvent_ e
  {-# INLINABLE performEvent #-}
  performEvent e = lift $ performEvent e

instance PostBuild t m => PostBuild t (HydrationDomBuilderT t m) where
  {-# INLINABLE getPostBuild #-}
  getPostBuild = lift getPostBuild

instance MonadReflexCreateTrigger t m => MonadReflexCreateTrigger t (HydrationDomBuilderT t m) where
  {-# INLINABLE newEventWithTrigger #-}
  newEventWithTrigger = lift . newEventWithTrigger
  {-# INLINABLE newFanEventWithTrigger #-}
  newFanEventWithTrigger f = lift $ newFanEventWithTrigger f

instance (Monad m, MonadRef m, Ref m ~ Ref IO, MonadReflexCreateTrigger t m) => TriggerEvent t (HydrationDomBuilderT t m) where
  {-# INLINABLE newTriggerEvent #-}
  newTriggerEvent = HydrationDomBuilderT . lift . lift $ newTriggerEvent
  {-# INLINABLE newTriggerEventWithOnComplete #-}
  newTriggerEventWithOnComplete = HydrationDomBuilderT . lift . lift $ newTriggerEventWithOnComplete
  {-# INLINABLE newEventWithLazyTriggerWithOnComplete #-}
  newEventWithLazyTriggerWithOnComplete f = HydrationDomBuilderT . lift . lift $ newEventWithLazyTriggerWithOnComplete f

instance HasJSContext m => HasJSContext (HydrationDomBuilderT t m) where
  type JSContextPhantom (HydrationDomBuilderT t m) = JSContextPhantom m
  askJSContext = lift askJSContext

instance MonadRef m => MonadRef (HydrationDomBuilderT t m) where
  type Ref (HydrationDomBuilderT t m) = Ref m
  {-# INLINABLE newRef #-}
  newRef = lift . newRef
  {-# INLINABLE readRef #-}
  readRef = lift . readRef
  {-# INLINABLE writeRef #-}
  writeRef r = lift . writeRef r

instance MonadAtomicRef m => MonadAtomicRef (HydrationDomBuilderT t m) where
  {-# INLINABLE atomicModifyRef #-}
  atomicModifyRef r = lift . atomicModifyRef r

instance (HasJS x m, ReflexHost t) => HasJS x (HydrationDomBuilderT t m) where
  type JSX (HydrationDomBuilderT t m) = JSX m
  liftJS = lift . liftJS

{-# INLINABLE wrapDomEvent #-}
wrapDomEvent :: (TriggerEvent t m, MonadJSM m) => e -> (e -> EventM e event () -> JSM (JSM ())) -> EventM e event a -> m (Event t a)
wrapDomEvent el elementOnevent getValue = wrapDomEventMaybe el elementOnevent $ fmap Just getValue

{-# INLINABLE subscribeDomEvent #-}
subscribeDomEvent :: (EventM e event () -> JSM (JSM ()))
                  -> EventM e event (Maybe a)
                  -> Chan [DSum (EventTriggerRef t) TriggerInvocation]
                  -> EventTrigger t a
                  -> JSM (JSM ())
subscribeDomEvent elementOnevent getValue eventChan et = elementOnevent $ do
  mv <- getValue
  forM_ mv $ \v -> liftIO $ do
    --TODO: I don't think this is quite right: if a new trigger is created between when this is enqueued and when it fires, this may not work quite right
    etr <- newIORef $ Just et
    writeChan eventChan [EventTriggerRef etr :=> TriggerInvocation v (return ())]

instance MonadSample t m => MonadSample t (HydrationDomBuilderT t m) where
  {-# INLINABLE sample #-}
  sample = lift . sample

instance MonadHold t m => MonadHold t (HydrationDomBuilderT t m) where
  {-# INLINABLE hold #-}
  hold v0 v' = lift $ hold v0 v'
  {-# INLINABLE holdDyn #-}
  holdDyn v0 v' = lift $ holdDyn v0 v'
  {-# INLINABLE holdIncremental #-}
  holdIncremental v0 v' = lift $ holdIncremental v0 v'
  {-# INLINABLE buildDynamic #-}
  buildDynamic a0 = lift . buildDynamic a0
  {-# INLINABLE headE #-}
  headE = lift . headE
