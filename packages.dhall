let upstream =
      https://raw.githubusercontent.com/working-group-purescript-es/package-sets/main/packages.dhall
        sha256:bed8d3f7fcac6fed46b9b327378b2303a1801706d35ad502156c62e9ddc906e7

in  upstream
  -- `elmish-enzyme` and `elmish-html` are used in integration tests. Because
  -- they both depend on Elmish, we have to remove Elmish from their
  -- dependencies, otherwise Spago will install another copy of Elmish from the
  -- package set, and we'll end up with two copies of Elmish, leading to module
  -- name conflicts during compilation.
  -- with elmish-enzyme.dependencies = [ "prelude" ]
  -- with elmish-enzyme.version = "v0.0.2"
  -- with elmish-html.dependencies = [ "prelude", "record" ]
  with metadata.version = "v0.15.0"
