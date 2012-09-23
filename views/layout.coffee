  head ->
    meta charset: 'utf-8'
    meta name:"viewport", content:"width=device-width, initial-scale=1.0, user-scalable = no"
    meta name: "apple-mobile-web-app-capable", content:"yes"
    #link href: "/css/bootstrap-responsive.css", rel: "stylesheet"
    
    title "#{@title or 'Untitled'} | Swyp"

    if @stylesheets
      for s in @stylesheets
        link rel: 'stylesheet', href: s + '.css'
    link(rel: 'stylesheet', href: @stylesheet + '.css') if @stylesheet
    style @style if @style
  
    if @localScripts
      for s in @localScripts
          script src: s + '.js'
 
  

  body ->
    div 'header navbar-static-top', ->
      div 'container-fluid', ->
        a  {href: "/"}, ->
          img 'homeHeader', src: "/img/adhearean-website-header-logo.png", ->
        div 'headerControls hidden-desktop visible-phone',->
          div 'btn-group', ->
            button 'btn btn-primary dropdown-toggle', 'data-toggle':'dropdown', href:'#', ->
              text "! "
              span 'caret', ->
            ul 'dropdown-menu pull-right', ->
              if @localAuthor? == true
                li class:(if (this.parentView.name == 'code') then 'active' else ''), ->
                  a href:'/code', -> "Enter Code"
                li class:(if (this.parentView.name == 'rewards') then 'active' else ''), ->
                  a href:'/rewards', -> "My Rewards"
                li 'divider', ->
              li ->
                if @localAuthor? == false
                  a '', {href:"javascript:void(0)", onclick: 'window.loginPressed.apply()'}, -> 'Login'
                else
                  a '', {href:"/logout"}, -> 'Logout'

        div 'headerControls hidden-phone', ->
          if @message?
            div 'headerAlert', ->
              text @message
          ul 'nav nav-pills inline', ->
            li class:(if (this.parentView.name == 'code') then 'active' else ''), ->
              a href:'/code', -> "Enter Code"
            li class:(if (this.parentView.name == 'rewards') then 'active' else ''), ->
              a href:'/rewards', -> "My Rewards"
          
          if @localAuthor? == false
            a 'userLoginOutButton btn btn-primary btn-small', {href:"javascript:void(0)", onclick: 'window.loginPressed.apply()'}, -> 'Login'
          else
            a 'userLoginOutButton btn btn-primary btn-small', {href:"/logout"}, -> 'Logout'
   
    @body

  body ->
   footer ->
    text 'Adherean, Inc.'

  body ->
    if @scripts
      for s in @scripts
          script src: s + '.js'
    

