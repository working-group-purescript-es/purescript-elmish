---
title: Composition
---

> **Under construction**. This page is unfinished. Many headings just have some bullet points sketching the main points that should be discussed.

In a real program, it is almost never enough to have all of the UI logic and visuals in one place. Almost always it is beneficial to split up the UI into smaller parts, usually located in separate modules, be it for clarity and maintainability or for reuse.

This page describes different patterns of such decomposition supported by Elmish.

## View functions

The simplest way to split up a big UI is to extract some parts of its `view` function as separate functions, what in some contexts might be called "partial view". For example, consider the bespoke counter UI:

```haskell
type State = { count :: Int }
data Message = Inc | Dec

view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.div ""
  [ H.div "" $ "The current count is: " <> show state.count
  , button "increase" (dispatch Inc)
  , button "decrease" (dispatch Dec)
  ]

button :: String -> Effect Unit -> ReactElement
button text onClick =
  H.div ""
  [ H.text $ "To " <> text <> " the count, click here: "
  , H.button_ "btn btn-primary" { onClick } text
  ]
```

Here, we have extracted the visuals for "increase" and "decrease" buttons as a partial view function named `button`, which is then used twice in the main `view` function.

> **NOTE:** such "partial view" function doesn't have to be just a visual. As seen in this example, it can produce messages as well.

Often, especially with larger partial views, it's beneficial to name their parameters by gathering them in a record:

```haskell
view :: State -> Dispatch Message -> ReactElement
view state dispatch =
  H.div ""
  [ H.div "" $ "The current count is: " <> show state.count
  , button { text: "increase", onClick: dispatch Inc }
  , button { text: "decrease", onClick: dispatch Dec }
  ]

button :: { text :: String, onClick :: Effect Unit } -> ReactElement
button { text, onClick } =
  H.div ""
  [ H.text $ "To " <> text <> " the count, click here: "
  , H.button_ "btn btn-primary" { onClick } text
  ]
```


* Elm-style
    * Unwrap/rewrap
    * Bifunctor
    * Monad
* View-only
* Dedicated event loop
