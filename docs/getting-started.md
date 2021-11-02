# Getting Started with Elmish

## Requisite tools

Elmish is a PureScript library, and PureScript works with
[NodeJS](https://nodejs.org/en/download/), and that's pretty much the only tool
you'll need to install upfront.

## Initialize an empty project

First, create a directory and set up the tool chain in it:

1. Create an empty directory
2. Run `npm init` to initialize a new Node project in the directory. This will
   ask you a bunch of questions, but you can just hit Enter to all of them,
   they're not important. The result should be a lone `package.json` file in the
   directory.
3. Run `npm install --save purescript spago react react-dom` to install:
    * `purescript` - the PureScript compiler.
    * `spago` - [the PureScript package manager](https://github.com/purescript/spago).
    * `react` and `react-dom` - the React library, on which Elmish is based.
4. Run `npx spago init` to initialize a new PureScript project in the directory.
   This should create a bit of scaffolding, including a couple of `*.dhall` files
   and an `src` directory with `Main.purs` in it.
5. Run `npx spago install elmish elmish-html` to install the Elmish library and
   its companion `elmish-html`.

Now that you have the barebones project, add a way to run and test it:

1. Using your favourite text editor, create a file named `index.html` and put
   the following code in it:

   ```html
    <div id="app">The UI is not here yet</div>
    <script src="output/index.js"></script>
    <script>window.Main.main()</script>
   ```

   The first line is the container for the application to render itself in. The
   second line references the JavaScript bundle (result of your code
   compilation). The third line invokes the PureScript entry point function.

2. Open `package.json`, find the `scripts` section in it, and add the following line:

   ```json
   "start": "spago build && esbuild ./output/Main/index.js --bundle --serve --servedir=. --outfile=output/index.js --global-name=Main"
   ```

   This command first builds your project (via `spago build`) and then starts
   the `esbuild` bundler to bundle the compilation results and simultaneously
   serve them with a built-in web server.

3. To verify, run `npm start`. This should, after a few seconds, display
   something along the lines of:

   ```text
   Local: http://127.0.0.1:8000/
   ```

   Open that address in a browser. You should see text "_The UI is not here
   yet_". If you don't see that, something is wrong with the setup so far.

## Write your first Elmish UI

