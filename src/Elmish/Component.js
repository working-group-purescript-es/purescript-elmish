const React = require("react")

exports.withCachedComponent = (function() {
  const cache = {}

  return function(name, f) {
    const c = cache[name] || (cache[name] = mkFreshComponent(name))
    return f(c)
  }
})()

exports.withFreshComponent = function(f) {
  return f(mkFreshComponent())
}

exports.instantiateBaseComponent = React.createElement

function mkFreshComponent(name) {
  class ElmishComponent extends React.Component {
    constructor(props) {
      super(props)
      props.init && props.init(this)()
    }

    render() {
      return this.props.render(this)()
    }

    componentDidMount() {
      this.props.componentDidMount(this)()
    }
  }

  ElmishComponent.displayName = name ? ("Elmish_" + name) : "ElmishRoot"
  return ElmishComponent
}
