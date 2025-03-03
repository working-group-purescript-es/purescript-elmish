module Elmish.Component
    ( Transition
    , Transition'(..)
    , Command
    , ComponentDef
    , ComponentDef'
    , ComponentReturnCallback
    , transition
    , fork, forks, forkVoid, forkMaybe
    , withTrace
    , nat
    , construct
    , wrapWithLocalState
    , ComponentName(..)
    , module Bifunctor
    ) where

import Prelude

import Data.Bifunctor (bimap, lmap, rmap) as Bifunctor
import Data.Bifunctor (class Bifunctor)
import Data.Function.Uncurried (Fn2, runFn2)
import Data.Maybe (Maybe, maybe)
import Debug as Debug
import Effect (Effect, foreachE)
import Effect.Aff (Aff, Milliseconds(..), delay, launchAff_)
import Effect.Class (class MonadEffect, liftEffect)
import Elmish.Dispatch (Dispatch)
import Elmish.React (ReactComponent, ReactComponentInstance, ReactElement)
import Elmish.State (StateStrategy, dedicatedStorage, localState)
import Elmish.Trace (traceTime)

-- | A UI component state transition: wraps the new state value together with a
-- | (possibly empty) list of effects that the transition has caused (called
-- | "commands"), with each command possibly producing some new messages.
-- |
-- | Instances of this type may be created either by using the smart constructor:
-- |
-- |     update :: State -> Message -> Transition' Aff Message State
-- |     update state m = transition state [someCommand]
-- |
-- | or in monadic style (see comments on `fork` for more on this):
-- |
-- |     update :: State -> Message -> Transition' Aff Message State
-- |     update state m = do
-- |         s1 <- Child1.update state.child1 Child1.SomeMessage # lmap Child1Msg
-- |         s2 <- Child2.modifyFoo state.child2 # lmap Child2Msg
-- |         fork someEffect
-- |         pure state { child1 = s1, child2 = s2 }
-- |
-- | or, for simple sub-component delegation, the `BiFunctor` instance may be
-- | used:
-- |
-- |     update :: State -> Message -> Transition' Aff Message State
-- |     update state (ChildMsg m) =
-- |         Child.update state.child m
-- |         # bimap ChildMsg (state { child = _ })
-- |
data Transition' m msg state = Transition state (Array (Command m msg))

-- A `Transition'` in which the effects run in `Aff`.
type Transition msg state = Transition' Aff msg state

-- | An effect that is launched as a result of a component state transition.
-- | It's a function that takes a callback, which allows it to produce (aka
-- | "dispatch") messages.
type Command m msg = (msg -> Effect Unit) -> m Unit

instance trBifunctor :: Functor m => Bifunctor (Transition' m) where
    bimap f g (Transition s cmds) = Transition (g s) (cmds <#> \cmd sink -> cmd $ sink <<< f)
instance trFunctor :: Functor (Transition' m msg) where
    map f (Transition x cmds) = Transition (f x) cmds
instance trApply :: Apply (Transition' m msg) where
    apply (Transition f cmds1) (Transition x cmds2) = Transition (f x) (cmds1 <> cmds2)
instance trApplicative :: Applicative (Transition' m msg) where
    pure a = Transition a []
instance trBind :: Bind (Transition' m msg) where
    bind (Transition s cmds) f =
        let (Transition s' cmds') = f s
        in Transition s' (cmds <> cmds')
instance trMonad :: Monad (Transition' m msg)

-- | Smart constructor for the `Transition'` type. See comments there. This
-- | function takes the new (i.e. updated) state and an array of commands - i.e.
-- | effects producing messages - and constructs a `Transition'` out of them
transition :: forall m state msg. Bind m => MonadEffect m => state -> Array (m msg) -> Transition' m msg state
transition s cmds =
    Transition s $ cmds <#> \cmd sink -> do
        msg <- cmd
        liftEffect $ sink msg

-- | Creates a `Transition'` that contains the given command (i.e. a
-- | message-producing effect). This is intended to be used for "accumulating"
-- | effects while constructing a transition in imperative-ish style. When used
-- | as an action inside a `do` block, this function will have the effect of
-- | "adding the command to the list" to be executed. The name `fork` reflects
-- | the fact that the given effect will be executed asynchronously, after the
-- | `update` function returns.
-- |
-- | In more precise terms, the following:
-- |
-- |     trs :: Transition' m Message State
-- |     trs = do
-- |         fork f
-- |         fork g
-- |         pure s
-- |
-- | Is equivalent to this:
-- |
-- |     trs :: Transition' m Message State
-- |     trs = transition s [f, g]
-- |
-- | At first glance it may seem that it's shorter to just call the `transition`
-- | smart constructor, but monadic style comes in handy for composing the
-- | update out of smaller pieces. Here's a more full example:
-- |
-- |     data Message = ButtonClicked | OnNewItem String
-- |
-- |     update :: State -> Message -> Transition' Aff Message State
-- |     update state ButtonClick = do
-- |         fork $ insertItem "new list"
-- |         incButtonClickCount state
-- |     update state (OnNewItem str) =
-- |         ...
-- |
-- |     insertItem :: Aff Message
-- |     insertItem name = do
-- |         delay $ Milliseconds 1000.0
-- |         pure $ OnNewItem name
-- |
-- |     incButtonClickCount :: Transition' Aff Message State
-- |     incButtonClickCount state = do
-- |         forkVoid $ trackingEvent "Button click"
-- |         pure $ state { buttonsClicked = state.buttonsClicked + 1 }
-- |
fork :: forall m message. MonadEffect m => m message -> Transition' m message Unit
fork cmd = transition unit [cmd]

-- | Similar to `fork` (see comments there for detailed explanation), but the
-- | parameter is a function that takes a message-dispatching callback. This
-- | structure allows the command to produce zero or multiple messages, unlike
-- | `fork`, whose callback has to produce exactly one.
-- |
-- | Example:
-- |
-- |     update :: State -> Message -> Transition' Aff Message State
-- |     update state msg = do
-- |         forks countTo10
-- |         pure state
-- |
-- |     countTo10 :: Command Aff Message
-- |     countTo10 msgSink =
-- |         for_ (1..10) \n ->
-- |             delay $ Milliseconds 1000.0
-- |             msgSink $ Count n
-- |
forks :: forall m message. Command m message -> Transition' m message Unit
forks cmd = Transition unit [cmd]

-- | Similar to `fork` (see comments there for detailed explanation), but the
-- | effect doesn't produce any messages, it's a fire-and-forget sort of effect.
forkVoid :: forall m message. m Unit -> Transition' m message Unit
forkVoid cmd = forks $ const cmd

-- | Similar to `fork` (see comments there for detailed explanation), but the
-- | effect may or may not produce a message, as modeled by returning `Maybe`.
forkMaybe :: forall m message. MonadEffect m => m (Maybe message) -> Transition' m message Unit
forkMaybe cmd = forks \sink -> do
    msg <- cmd
    liftEffect $ maybe (pure unit) sink msg

-- | Definition of a component according to The Elm Architecture. Consists of
-- | three functions - `init`, `view`, `update`, - that together describe the
-- | lifecycle of a component.
-- |
-- | Type parameters:
-- |
-- |   * `m` - a monad in which the effects produced by `update` and `init`
-- |     functions run.
-- |   * `msg` - component's message.
-- |   * `state` - component's state.
type ComponentDef' m msg state = {
    init :: Transition' m msg state,
    view :: state -> Dispatch msg -> ReactElement,
    update :: state -> msg -> Transition' m msg state
}

-- | A `ComponentDef'` in which effects run in `Aff`.
type ComponentDef msg state = ComponentDef' Aff msg state

-- | A callback used to return multiple components of different types. See below
-- | for a more detailed explanation.
-- |
-- | This callback is handy in situations where a function must return different
-- | components (with different `state` and `message` types) depending on
-- | parameters. The prime example of such situation is routing.
-- |
-- | Because most routes are served by different UI components, with different
-- | `state` and `message` type parameters, the instantiating functions cannot
-- | have the naive signature `route -> component`: they need to "return"
-- | differently-typed results depending on the route. In order to make that
-- | happen, these functions instead take a polymorphic callback, to which they
-- | pass the UI component. This type alias is the type of such callback: it
-- | takes a polymorphically-typed UI component and returns "some value", a la
-- | continuation-passing style.
-- |
-- | Even though this type is rather trivial, it is included in the library for
-- | the purpose of attaching this documentation to it.
type ComponentReturnCallback m a =
    forall state msg. ComponentDef' m msg state -> a

-- | Wraps the given component, intercepts its update cycle, and traces (i.e.
-- | prints to dev console) every command and every state value (as JSON
-- | objects), plus timing of renders and state transitions.
withTrace :: forall m msg state
     . Debug.DebugWarning
    => ComponentDef' m msg state
    -> ComponentDef' m msg state
withTrace def = def { update = tracingUpdate, view = tracingView }
    where
        tracingUpdate s m =
            let (Transition s cmds) = traceTime "Update" \_ -> def.update s $ Debug.spy "Message" m
            in Transition (Debug.spy "State" s) cmds
        tracingView s d =
            traceTime "Rendering" \_ -> def.view s d

-- | Takes a component definition (i.e. init+view+update functions) and
-- | "renders" it as a React DOM element, suitable for passing to
-- | `ReactDOM.render` or embedding in a JSX DOM tree.
bindComponent :: forall msg state
     . BaseComponent                 -- ^ A JS class inheriting from React.Component to serve as base
    -> ComponentDef msg state        -- ^ The component definition
    -> StateStrategy state           -- ^ Strategy of storing state
    -> ReactElement
bindComponent cmpt def stateStrategy =
    runFn2 instantiateBaseComponent cmpt { init: initialize, render, componentDidMount: runCmds initialCmds }
    where
        Transition initialState initialCmds = def.init

        {initialize, getState, setState} = stateStrategy {initialState}

        render :: ReactComponentInstance -> Effect ReactElement
        render component = do
            state <- getState component
            pure $ def.view state $ dispatchMsg component

        dispatchMsg :: ReactComponentInstance -> Dispatch msg
        dispatchMsg component msg = do
            oldState <- getState component
            let Transition newState cmds = def.update oldState msg
            setState component newState $ runCmds cmds component

        runCmds :: Array (Command Aff msg) -> ReactComponentInstance -> Effect Unit
        runCmds cmds component = foreachE cmds runCmd
            where
                runCmd :: Command Aff msg -> Effect Unit
                runCmd cmd = launchAff_ do
                    delay $ Milliseconds 0.0 -- Make sure this call is actually async
                    cmd $ liftEffect <<< dispatchMsg component

-- | Given a `ComponentDef'`, binds that def to a freshly created React class,
-- | instantiates that class, and returns a rendering function. Note that the
-- | return type of this function is almost the same as that of
-- | `ComponentDef'::view` - except for state. This is not a coincidence: it is
-- | done this way on purpose, so that the result of this call can be used to
-- | construct another `ComponentDef'`.
-- |
-- | Unlike `wrapWithLocalState`, this function uses the bullet-proof strategy
-- | of storing the component state in a dedicated mutable cell, but that
-- | happens at the expense of being effectful.
construct :: forall msg state
     . ComponentDef msg state       -- ^ The component definition
    -> Effect ReactElement
construct def = do
    stateStorage <- liftEffect dedicatedStorage
    pure $ withFreshComponent $ \cmpt ->
        bindComponent cmpt def stateStorage

-- | Monad transformation applied to `ComponentDef'`
nat :: forall m n msg state. (m ~> n) -> ComponentDef' m msg state -> ComponentDef' n msg state
nat map def =
    {
        view: def.view,
        init: mapTransition def.init,
        update: \s m -> mapTransition $ def.update s m
    }
    where
        mapTransition (Transition state cmds) = Transition state (mapCmd <$> cmds)
        mapCmd cmd sink = map $ cmd sink

-- | Creates a React component that can be bound to a varying `ComponentDef'`,
-- | returns a function that performs the binding.
-- |
-- | Note 1: this function accepts an `Aff`-based `ComponentDef'`, it cannot
-- | take polymorphic or custom monad. The superficial reason for this is that
-- | this function is intended to be used at top-level (see explanation below),
-- | where context for a custom monad is not available. A deeper reason is that
-- | this function creates a self-contained React component, and it is precisely
-- | because it is self-contained that it cannot be seamlessly included in an
-- | outer monadic computation.
-- |
-- | This limitation forces such truly "reusable" components to be written in
-- | terms of `Aff` rather than a custom monad, which is actually a good thing.
-- | However, if it turns out that this component really needs to be in a custom
-- | monad, it is always possible to convert it to `Aff` via the `nat` function.
-- |
-- | Note 2: in order to accomplish this, such aggregated component will store
-- | its state using the React facilities - i.e. via `this.setState` and
-- | `this.state`. While this is appropriate for most cases, it actually has
-- | proven to be fragile in some specific circumstances (e.g. multiple events
-- | occurring within the same JS synchronous frame), so it is not recommended
-- | to use this mechanism for complex components or the top-level program.
wrapWithLocalState :: forall msg state args
     . ComponentName
    -> (args -> ComponentDef msg state)
    -> args
    -> ReactElement
wrapWithLocalState name mkDef =
    runFn2 withCachedComponent name $ \cmpt args ->
        bindComponent cmpt (mkDef args) localState

-- | A unique name for a component created via `wrapWithLocalState`. These names
-- | don't technically need to be _completely_ unique, but they do need to be
-- | unique enough so that two different `wrapWithLocalState`-created components
-- | that happen to have the same name never replace each other in the DOM. For
-- | this reason, it is recommended to actually make sure these names are
-- | unique, for example by appending a GUID to them. Read on for a more
-- | detailed explanation.
-- |
-- | React uses referential equality to decide whether to create a new instance
-- | of a component (and thus reset its local state) or keep the existing
-- | instance. This means that, on one hand, we cannot use the same React class
-- | for every instantiation, because this may create conflicts, where one
-- | Elmish component replaces another in the DOM, but they look like the same
-- | component to React, which makes it reuse state, which leads to breaking
-- | type safety. On the other hand, we cannot create a fresh class on every
-- | render, because then React will see it as a new component every time, and
-- | will reset its state every time.
-- |
-- | This means that we need some way of figuring out whether it needs to be
-- | logically the "same" component or "different", but there is no way to get that
-- | "for free" (same way React gets it for free from referential equality) due
-- | to PureScript's purity. Therefore, the only reliable way is to ask the
-- | programmer, which is accomplished by requiring a `ComponentName`, which
-- | serves as a key.
newtype ComponentName = ComponentName String

--
--
--

-- Props for the React component that is used as base for this framework. The
-- component itself is defined in the foreign module.
type BaseComponentProps = {
    init :: ReactComponentInstance -> Effect Unit,
    render :: ReactComponentInstance -> Effect ReactElement,
    componentDidMount :: ReactComponentInstance -> Effect Unit
}

type BaseComponent = ReactComponent BaseComponentProps

-- This is just a call to `React.createElement`, but we can't use the
-- general-purpose `createElement` function from `./React.purs`, because it
-- requires that the props type be "plain JavaScript" (i.e. have a
-- CanPassToJavaScript instance), and these props here are not that. It would be
-- possible to make this type passable to JS by using `Foreign` and maybe even
-- `unsafeCoerce` in places, but I have decided it wasn't worth it, because this
-- is just one place at the core of the framework.
foreign import instantiateBaseComponent :: Fn2 BaseComponent BaseComponentProps ReactElement

-- | On first call with a given name, this function returns a fresh React class.
-- | On subsequent calls with the same name, it returns the same class. It has
-- | this weird CPS signature in order to prevent PureScript from optimizing out
-- | repeated calls.
--
-- This is essentially a hack, but not quite. It operates in the grey area
-- between PureScript and JavaScript. See comments on `ComponentName` for a more
-- detailed explanation.
foreign import withCachedComponent :: forall a. Fn2 ComponentName (BaseComponent -> a) a

-- | Creates a fresh React component on every call. This is similar to
-- | `withCachedComponent`, but without the cache - creates a new component
-- | every time.
foreign import withFreshComponent :: forall a. (BaseComponent -> a) -> a
