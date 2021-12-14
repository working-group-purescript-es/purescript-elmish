---
title: State Transitions
---

> **Under construction**. This page is unfinished. Many headings just have some bullet points sketching the main points that should be discussed.

The `update` function describes a UI state transition in response to a particular message. This transition consists of two components:

* the new state of the UI, and
* zero or more effects

Effects are monadic computations (usually in `Effect` or `Aff`), which do something useful, such as communicating with the server, accessing local storage, system clock, and so on, and as a result produce a new message, which then triggers another state transition, completing the loop.

A transition has type `Transition message state`, with the `state` type parameter indicating what type of state the transition describes, and the `message` parameter indicating what type of messages the effects in the transition would produce.

## State

The way to define the "new state" part of a transition is via `pure` (which works because the `Transition` type is a monad). For example, the bespoke counter UI might look something like this:

```haskell
type State = { count :: Int }
data Message = Inc | Dec

update :: State -> Message -> Transition Message State
update state Inc = pure $ state { count = state.count + 1 }
update state Dec = pure $ state { count = state.count - 1 }
```

Because `Transition` is a monad, the `update` function has access to all the monadic goodies, such as the `do` notation, composition, traversals, etc. For example:

```haskell
update :: State -> Message -> Transition Message State
update state Inc = modifyCount state 1
update state Dec = modifyCount state (-1)

modifyCount :: State -> Int -> Transition Message State
modifyCount state delta = do
  let newCount = state.count + delta
      newState = state { count = newCount }
  pure newState
```

## <a name="effects"></a>Effects

The high-level, most convenient way to add an effect to a transition is via the `fork` function. For example, if we wanted to make counter increments to happen with a delay, we might do something like this:

```haskell
data Message = Inc | Dec | StartInc

update :: State -> Message -> Transition Message State
update state Inc = pure $ state { count = state.count + 1 }
update state Dec = pure $ state { count = state.count - 1 }
update state StartInc = do
  fork do
    delay (Milliseconds 1000.0)
    pure Inc

  pure state
```

The block passed to the `fork` function is an `Aff` computation, which waits one seconds and then returns the `Inc` message. This message will then be fed right back into the `update` function, causing the state update to increase the count.

Sometimes it happens so that the computation may or may not produce a message depending on some external reasons. In this case, the `forkMaybe` function is handy. It takes an `Aff (Maybe message)` computation as a parameter, thus allowing for no message to be produced:

```haskell
update state StartInc = do
  forkMaybe do
    delay (Milliseconds 1000.0)
    r <- checkSomeCondition
    if r then pure (Just Inc) else pure Nothing

  pure state
```

For those effects that never produce any messages, regardless of external reasons, the function `forkVoid` may be used:

```haskell
update state StartInc = do
  forkMaybe do
    delay (Milliseconds 1000.0)
    r <- checkSomeCondition
    if r then pure (Just Inc) else pure Nothing

  forkVoid do
    Console.log "Hello!"

  pure state
```

> **NOTE**: in the last code snippet the transition has two separate effects: one waits a second and then optionally produces the `Inc` message, and the other prints to console right away and produces no message. This is perfectly legal: a transition may have an arbitrary number of effects, and they all get executed in parallel.

Finally, in the most complex cases, it may be necessary to produce multiple messages from a single computation. One example might be a long-running computation that reports its progress. For these cases, the most powerful `forks` function may be used. The `forks` function provides a callback that can be used to "issue" (or "dispatch") a message. For example:

```haskell
update state StartInc = do
  forks \dispatch -> do
    delay (Milliseconds 1000.0)
    dispatch Inc
    delay (Milliseconds 2000.0)
    dispatch Inc
    delay (Milliseconds 3000.0)
    dispatch Inc

  pure state
```

In this example the effectful computation produces one `Inc` message after a second, another one 2 seconds after that, and a third after 3 more seconds.

## Under the hood


## Manipulating transitions

* unwrap/rewrap -> bifunctor -> monad
* Link to (composition)[composition.md]
