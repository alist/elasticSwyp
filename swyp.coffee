primaryHost = "https://swypserver.herokuapp.com"
secrets = require ('./secrets')
request = require 'request'
mongoose     = require('mongoose')
Schema = mongoose.Schema

ObjectId = mongoose.SchemaTypes.ObjectId

#authors are users
AuthorSchema = new Schema {
  modifiedDate: {type: Date, index: {unique: false}}
  displayName: String
  imageURI: String
  authorID: {type: String, required: true, index: {unique: true}}

  fbAccessToken: {type: String}
  facebookID: {type: Number, index: {unique: true}}
  isAdmin: {type: Boolean}

}

Author = mongoose.model 'Author', AuthorSchema

`Array.prototype.unique = function() {    var o = {}, i, l = this.length, r = [];    for(i=0; i<l;i+=1) o[this[i]] = this[i];    for(i in o) r.push(o[i]);    return r;};`

swypApp = require('zappa').app ->
  mongoose.connect(secrets.mongoDBConnectURLSecret)
  @use 'bodyParser', 'static', 'cookies', 'cookieParser', session: {secret: secrets.sessionSecret}

  crypto = require('crypto')
 
  #we want https
  @get '*': ->
    if @request.headers['host'] == '127.0.0.1:3000' || @request.headers['host'] == 'localhost:3000'
      @next()
    else if @request.headers['x-forwarded-proto']!='https'
      @redirect "#{primaryHost}#{@request.url}"
    else
      @next()

  @get '/': ->
    sessionToken = @request.cookies?.sessiontoken
    authCurrentAuthorWithIDAndTokenForSession null, null, sessionToken, (err, author) =>
      @render index: {localAuthor:author}
  
  @get '/rewards': ->
    sessionToken = @request.cookies?.sessiontoken
    authCurrentAuthorWithIDAndTokenForSession null, null, sessionToken, (err, author) =>
      if author?
        Author.findOne({_id: author._id}).populate('rewardOptions').populate('rewards').exec (err, author) =>
          RewardOption.find {}, {}, null, (err, rewardOptions) =>
            @render rewards: {localAuthor: author, rewardOptions: rewardOptions}
      else
        @render index: {message: "login first", locals:{ redirectURL: @request.originalUrl}, localAuthor:author}
    
  @get '/code': ->
    sessionToken = @request.cookies?.sessiontoken
    authCurrentAuthorWithIDAndTokenForSession null, null, sessionToken, (err, author) =>
      if author?
        @render code: {localAuthor: author}
      else
        @render index: {message: "login first", locals:{ redirectURL: @request.originalUrl}, localAuthor:author}
 
  @get '/redeem/:id', (req, res) ->
    @redirect '/'
 
  @post '/apiv1/submitCode', (req, res) ->
    sessionToken = @request.cookies?.sessiontoken
    console.log req.body
    code = req.body.code
    authCurrentAuthorWithIDAndTokenForSession null, null, sessionToken, (err, author) =>
      if author? && code?.length >= 4
        newCode = new SubmittedCode {code: code, submitDate: new Date()}
        newCode.rewardURL = "#{primaryHost}/rewards/#{newCode._id}"
        submittedCodes = if (author.submittedCodes)? then author.submittedCodes else []
        submittedCodes.push newCode
        author.submittedCodes = submittedCodes
        author.save (error) =>
          if error? == false
            generateRewardForAuthorForSubmittedCode author, newCode, (err, reward, fullAuthor) =>
              console.log "rewarded #{reward} author #{fullAuthor._id}"
              @response.send {submittedCode: newCode, reward: reward, rewardOptions:fullAuthor?.rewardOptions, status: 'success'}
          else
            @response.send {status: 'failed', reason: error}
      else
        @response.send {status: 'failed'}
  
  generateRewardForAuthorForSubmittedCode = (author, code, callback) -> #callback(err, reward, populatedAuthor)
    if author.rewardOptions? == false
      callback "no reward options chose for authorID: #{author._id}"
      return
    Author.findOne({_id: author._id}).populate('rewardOptions').exec (err, author) =>
      rewardOptionsCount = author.rewardOptions?.length
      rewardOptionNumber = Math.floor(Math.random()*rewardOptionsCount) #random from 0->rewardOptionsCt -1
      rewardOption = author.rewardOptions[rewardOptionNumber]

      #here's how we find out which option is chose: we get a random val <= 1, then we add each rewardPobability's Quantity togeather and the first added that's greater than the random number is the reward options that's good
      randLessThanOne = Math.random()
      rewardQuantity = null
      probabilitySum = 0
      for quantityGroup in rewardOption.rewardQuantities
        probabilitySum = probabilitySum + quantityGroup.probability
        if probabilitySum > randLessThanOne
          rewardQuantity = quantityGroup.quantity
          console.log "found rewardQuantity #{rewardQuantity} for option: #{rewardOption}"
          break
    
      Author.findOne({_id: author._id}).populate('rewardOptions').populate('rewards').exec (err, author) =>
        rewardItem = null
        for reward in author?.rewards
          if reward.rewardOption.toString() == rewardOption._id.toString()
            rewardItem = reward
            break
        if rewardItem? == false
          rewardItem = new Reward {rewardOption: rewardOption._id, issuances:[], totalQuantity: 0}
          rewardItem.redeemURL = "#{primaryHost}/redeem/#{rewardItem._id.toString()}"
          Author.update {_id: author._id}, {$push: {rewards: rewardItem._id}},0,0, (error) =>
            console.log "updated author id #{author._id} to have new rewardItem inside it with error: #{error}"
        rewardItem.issuances.push {issueDate: new Date(), quantity: rewardQuantity, submittedCode: code._id}
        rewardItem.totalQuantity = (rewardItem.totalQuantity + rewardQuantity)
        rewardItem.save (err) =>
          console.log "Saved reward item#{rewardItem}"
          callback null, rewardItem, author
  
  assignAuthorNewReader = (author, reader, callback) -> #callback(err, author, reader)
    #Reader.findOne {forAuthor: {$exists: false}}, {}, (err, freeReader) =>
    if author? == false
      callback "no author"
    if reader? == false
      reader = new Reader {initializeDate: new Date, version: 1}
      reader.identifier = reader._id.toString()
    reader.owningAuthor = author._id
    reader.save (error) =>
      if error?
        callback error
        return
      readers = if (author.readers)? then author.readers else []
      readers.push reader._id
      author.readers = readers
      author.save (error) =>
        callback null, author, reader
  
  setAuthorDefaultsIfNeeded = (author, callback) -> #callback(author)  

    checkRewardOptionsFunction = (author, callback) -> #callback(author)
      if author.rewardOptions? == false || author.rewardOptions.length  < 1
        rewardOptions = if (author.rewardOptions)? then author.rewardOptions else []
        #we'll just add all reward options!
        RewardOption.find {}, {}, null, (err, allOptions) =>
          for option in allOptions
            rewardOptions.push option._id

          author.rewardOptions = rewardOptions
          author.save (error) =>
            console.log "assigned author #{author.displayName} defaultRewardOptionsIDs #{author.rewardOptions} with error #{error}"
            callback author
      else
        callback author

    if author.readers? == false || author.readers?.length < 1
      assignAuthorNewReader author, null, (err, author, reader) =>
        console.log "assigned author #{author.displayName} readerID #{reader.identifier}"
        
        checkRewardOptionsFunction author, (retAuthor) =>
          callback author

    else
      checkRewardOptionsFunction author, (retAuthor) =>
        callback retAuthor

  @get '/login', (req, res) ->
    fbAccessToken = req.query.token
    sessionToken = @request.cookies?.sessiontoken
    
    if sessionToken? == false
      current_date = (new Date()).valueOf().toString()
      random = Math.random().toString()
      hash = crypto.createHash('sha1').update(current_date + random).digest('hex')
      sessionToken = "OFFER_#{hash}"
      if @request.headers['host'] == 'localhost:3000'
         req.response.cookie 'sessiontoken', sessionToken, {httpOnly: true, maxAge: 90000000000 }
      else
         req.response.cookie 'sessiontoken', sessionToken, {httpOnly: true, secure: true, maxAge: 90000000000 }
  
    authCurrentAuthorWithIDAndTokenForSession null, fbAccessToken, sessionToken, (err, author) =>
      if author?
        console.log "auth or create for sessionid# #{sessionToken} finished with err #{err}"
        #we'll update with some newer stuff if need-be here
        setAuthorDefaultsIfNeeded author, (updatedAuthor) =>
          redirectURL = req.query.redirectURL
          if redirectURL
            @redirect redirectURL
          else
            @redirect '/'
      else
        redirectURL = req.query.redirectURL
        console.log "bad login for author w/ redirect #{redirectURL}, token #{fbAccessToken} and err #{err}"
        @render index: {message: "login denied; please login", locals:{ redirectURL:redirectURL}}

  @get '/logout', (req, res)->
    req.response.clearCookie 'sessiontoken' # clear the cookie
    req.redirect '/'
 
  ## DONE FUNCTIONS ##
  authCurrentAuthorWithIDAndTokenForSession = (authorID, fbAToken, sessionToken, callback) -> #callback(err, author)
    if sessionToken? == false
      callback "no sessionToken included for authorID author lookup"
      return
    
    #Strategy 1: find existing session
    Author.findOne {activeSessionIDs: sessionToken},{}, (err, author) =>
      console.log "found author w. ID #{author?.authorID} for session #{sessionToken}"
      if err? || author? == false
        #strategy 2: query fb with fbAToken, then check for existing authorIDs of equal to FB's response
        authUserWithFacebookOfIDAndToken authorID, fbAToken, (err, fbUserID, fbResponse) =>
          if err? || ((fbUserID != authorID) && authorID? == true) ##if there is mismatch when authorID!=nil
            callback "could not find author with pre-id #{authorID} with fbID #{fbUserID} with error #{err}"
          else
            if authorID? == false
              #if prior authorID was unknown by request, we'll check to see if we have a match right now from FB
              console.log "using recursion to determine if fbUserID exists, now that we know it's #{fbUserID}"
              authCurrentAuthorWithIDAndTokenForSession fbUserID, fbAToken, sessionToken, callback
            else
              #we've authed the token using FB, and the userID probably exists
              imgURI = "https://graph.facebook.com/#{fbUserID}/picture?type=large&return_ssl_resources=1"
              authorInfo = {authorID: fbUserID, facebookID: fbUserID, fbAccessToken: fbAToken, imageURI: imgURI, displayName: fbResponse.name, modifiedDate: new Date()}
              authorInfo.metroAreaDisplayName = fbResponse.location?.name
              
              console.log "create the author! with info #{authorInfo}"
              Author.update {authorID: fbUserID},{$set: authorInfo, $push: { activeSessionIDs: sessionToken}}, {upsert: 1}, (err) ->
                if err?
                  callback "error for author save #{err} with info #{authorInfo}"
                else
                  console.log "saved new author with info #{authorInfo}, using recursion for auth"
                  authCurrentAuthorWithIDAndTokenForSession fbUserID, fbAToken, sessionToken, callback
      else
        callback null, author
  
  authUserWithFacebookOfIDAndToken = (fbID, fbToken, callback) -> #callback (err, fbUserID, responseData) #with err if invalid token
    if fbToken? == false
      callback "missing token for fb req"
      return
    requestURL = "https://graph.facebook.com/me?access_token=#{fbToken}"
    console.log "doing request to fb with url: #{requestURL}"
    request requestURL, (error, response, body) ->
      if error? || response.statusCode != 200
        callback "fbreq err #{error} with code #{response.statusCode}"
        return
      resObjects = JSON.parse body
      if resObjects?.id != fbID
        console.log "fbreq mismatched fbID from req #{fbID} from server #{resObjects?.id}"
      if resObjects?.id? == false
        callback "no fbID returned for token #{fbToken}"
      else
        callback null, resObjects.id, resObjects

 
  getConcertsRelevantToRatingsInArtistsWithAuthor = (artists, author, callback) -> #callback(err, concerts)
    authorID = author.authorID.toString()
    relevantConcertIDs = []
    for artist in artists
      for rating in artist.ratings
        if rating.author.authorID == authorID
          relevantConcertIDs.push rating.concertID
    #console.log "authorID #{authorID} has relevant concertIDs #{relevantConcertIDs}"
    Concert.find {concertID: {$in: relevantConcertIDs}}, {feedItems: 0}, null, (err, docs) =>
      callback err, docs

  getAuthorWithID = (authorID, callback) -> #callback(err, author, abreviatedInfo)
    Author.findOne {authorID: authorID},{fbAccessToken:0, facebookID: 0}, (err, author) =>
      if err? || author? == false
        callback "could not find author of id #{authorID} with error #{err}"
      else
        authorInfo = {imageURI: author.imageURI, authorID: author.authorID.toString(), metroAreaDisplayName: author.metroAreaDisplayName, displayName: author.displayName, ratingCount: author.ratingCount}
        callback null, author, authorInfo
 
  feedItemsConcertWithConcertID = (concertID, lastUpdate, callback) -> #callback (error, concertWithFeed)
    if lastUpdate == 0 || lastUpdate? == false
      Concert.findOne {concertID: concertID},{concertID: 1, feedItems: {$slice:-40}}, (err, concert) =>
        if concert?
          concert.venue = undefined
          callback null, {concerts:[concert]}
        else
          callback "failed to get concert w. error #{err}"
    else
      Concert.findOne {concertID: concertID},{concertID: 1, feedItems:1}, (err, concert) =>
        if concert?
          feedItems = []
          for i in [concert.feedItems.length .. 0]
            if concert.feedItems?[i - 1]?.modifiedDate.getTime() < lastUpdate
              feedItems = concert.feedItems.slice(concert.feedItems.length - (i - 1))
              break
          response = {concerts:[{concertID:concert.concertID, feedItems:feedItems}]}
          callback null, response
        else
          callback "failed to get concert w. error #{err}"


  saveRatingWithPostData = (artistID, ratingPOST, callback) -> #(err, rating, artist) ->
    getArtistForIDGenerateIfNone artistID, (error, artist) =>
      #add review, recalculate rating, save
      if artist?
        Concert.findOne {concertID: ratingPOST.concertID}, (err, concert) =>
          if concert?

            getAuthorWithID ratingPOST.authorID, (err, author, authorInfo) =>
              if author?
                console.log "authorID", author.authorID
                rating = new Rating {author: authorInfo, artistID: artistID, concertDate: concert.startDateTime, concertID: concert.concertID, overallRating: ratingPOST.overallRating, stagePRating: ratingPOST.stagePRating, soundQRating: ratingPOST.soundQRating, visualsEffectsRating: ratingPOST.visualsEffectsRating, reviewText: ratingPOST.reviewText,modifiedDate: new Date()}
                rating.ratingID = rating._id
                artist.ratings.push rating
                cumRating = 0
                for ratVal in artist.ratings
                  cumRating += parseInt(ratVal.overallRating)
                artist.averageRating = cumRating/ artist.ratings.length
                artist.ratingCount = artist.ratings.length
                
                ratings = if author.ratingCount then author.ratingCount + 1 else 1
                toSet = { ratingCount: ratings }
                if concert.venue?.metroAreaDisplayName? == true
                  toSet.metroAreaDisplayName = concert.venue?.metroAreaDisplayName
                Author.update {_id: author._id}, {$set: toSet},0, (err) ->
                  console.log "updated author w. display name #{author.displayName} to rating count #{author.ratingCount + 1 } with error #{err}"
  
                #perhaps we should replace this with push when we get high load, but it takes only a few hundred miliseconds-- I can't imagine too many places with that kind of volume
                artist.save (err, savedArt) =>
                  if err?
                    callback err
                  else
                    savedRatingID = savedArt?.ratings?.slice(-1)?[0]?.ratingID
                    ### #here I'm adding the artist's artistID
                    Artist.update {authorID: artistID, 'ratings._id': savedRatingID}, {$set: {"ratings.$.ratingID": savedRatingID}},0,0, (err) ->
                      if err?
                        console.log "error adding ratingID to artist id##{artistID} rating #{savedRatingID}"
                        callback err
                      else
                        console.log "should have updated artist with ratingID #{savedRatingID}"

                    savedArt?.ratings?[savedArt.ratings.length - 1 ]?.ratingID = savedRatingID
                    ###
                    callback null, rating, savedArt
                    
                    feedItem = new FeedItem {modifiedDate: new Date(), author: authorInfo, ratingID: savedRatingID}
                    console.log "saved artist, now posting feedItem with ratingID #{savedRatingID}"
                    Concert.update {concertID: concert.concertID},{$push: { feedItems: feedItem }},0, (err) ->
                      if err?
                        console.log "Error posting rating id #{savedRatingID} to feed #{err}"
                      else
                        console.log "posted rating id #{savedRatingID} to concert id #{concert.concertID} feed"
              else
                callback "author error: #{err}"
          else
            callback "concert error: #{err}"
      else
        callback "artist error: #{error}"

  getArtistForIDGenerateIfNone = (aID, callback) -> #callback (error, artist)
    id = parseInt(aID)
    Artist.find {artistID: id}, null, null, (err, docs) =>
      if docs?[0]? == false
        console.log "Generating new artist entry based on concert data with id #{id}"
        Concert.find {'artists.artistID': id}, {feedItems: 0}, {limit:1}, (err, docs) =>
          #not going to songkick means that if we ever delete old artists, we risk trashing a user's old data
          if docs?[0]?
            copyFromArtist = null
            for itArtist in docs[0].artists
              if itArtist.artistID == id
                copyFromArtist = itArtist
            console.log "instantiating artist from concert w/ subArtist", copyFromArtist
            artist = new Artist copyFromArtist
            artist.save (err) ->
              if err?
                callback err, null
              else
                callback null, artist
          else
            error = "could not create artist: no artist info ever encountered, or no concerts available for artistID #{id}"
            callback error, null
      else
        callback null, docs[0]

  getHappeningConcertsNearLocation = (location, callback) -> #callback (error, concerts)
    radialKM = 1/6378 #in radial coord km/radiusEarth *ONLY WORKS ON EARTH*
    
    pastDate = new Date (new Date().getTime()-6*60*60*1000)
    futureDate = new Date (new Date().getTime()+6*60*60*1000)
    Concert.find {"venue.location": {$nearSphere: location, $maxDistance: radialKM * 50}, startDateTime: {$gte: pastDate, $lt: futureDate}}, {feedItems: 0}, {limit:200}, (err, concerts) =>
      if err?
        retErr =  "happening ConcertsNearLoc retrieval error #{err}"
        callback null, retErr
      else if concerts?
        callback concerts, null
      else
        retErr = "No happening concerts, but no retrieval errors"
        callback null, retErr

  #gets the Artists that match the artistIDs included in the Concert collection
  getArtistsRelevantToConcerts = (concerts, callback) -> #callback (error, artists)
    if concerts? == false
      err = "bad concerts data provided to get concerts"
      callback err, null
      return
    
    #grab artist IDs
    allArtistIDs = []
    for concert in concerts
      if concert.artists? == false
        console.log concert
      for artist in concert.artists
        allArtistIDs.push artist?.artistID
    
    Artist.find {artistID: {$in: allArtistIDs}}, null, null, (err, docs) =>
      callback err, docs

  #integrates the concerts updated from songkick with the existing server data 
  integrateEvents = (concerts, page, defaultLocation, callback) -> #callback (error, page)
    if concerts? == false || concerts.length == 0
      err = "bad concerts data provided integration error"
      callback err, page
    
    else for concertIter in [0..concerts.length - 1]
      do (concertIter) ->
        skEvent = concerts[concertIter]
        if skEvent? == false
          err = "messed up skevent ##{concertIter}..abort"
          callback err, page
          return
        #this concert will be rejected if it already exists because of unique concertIDs, this is needed funct
        artists = skEvent.performance
        artistHeadlining = artists?[0]?.displayName
        
        if artistHeadlining? == false || artistHeadlining == ""
          err = "no artists for skevent ##{concertIter} on page ##{page}"
          return

        openers = ""
        if artists.length > 1
          numbersOfArtists = artists.length
          for artIt in [1..artists.length - 1]
            if artIt == 1
              openers = artists[artIt]?.displayName
            else
              openers = openers.concat ", #{artists[artIt]?.displayName}"

        savingArtists = []
        for artistB in artists
          artist = artistB.artist
          artistImageURI = "http://topimage.herokuapp.com/#{artist.displayName} music"
          artistImageURI = artistImageURI.replace /\ /g, "-"
          savingArtists.push {displayName: artist.displayName, uri: artist.uri, imageURI: artistImageURI, artistID: artist.id}

        skVenue = skEvent.venue
        concertImageURI = "http://topimage.herokuapp.com/#{artistHeadlining} album"
        concertImageURI = concertImageURI.replace /\ /g, "-"

        if skVenue.lng? && skVenue.lat?
          location = [skVenue.lng, skVenue.lat]

        dateTime = skEvent.start?.datetime
        if dateTime? == false
          dateTime = skEvent.start?.date

        if skVenue?.id? == false
          console.log "no venueID for concertID #{skEvent?.id} -- skip obj# #{concertIter} of #{ (concerts.length) - 1} for page # #{page}"
          return #returns through do

        savingVenue = {venueID: skVenue.id, displayName: skVenue.displayName, metroAreaDisplayName: skVenue.metroArea?.displayName, uri: skVenue.uri, metroAreaID: skVenue.metroArea?.id}
        if skVenue.lng? && skVenue.lat?
          savingVenue.longitude = skVenue.lng
          savingVenue.latitude = skVenue.lat
          savingVenue.location = location
        else
          savingVenue.longitude = defaultLocation[0]
          savingVenue.latitude = defaultLocation[1]
          savingVenue.location = defaultLocation
          console.log "no location for concertID #{skEvent?.id}  -- setting default for obj# #{concertIter} of #{ (concerts.length) - 1} for page # #{page}"

        savingConcert = {concertID: skEvent.id, uri: skEvent.uri, imageURI: concertImageURI,  headliner: artistHeadlining, openers: openers, artists: savingArtists, venue: savingVenue, startDateTime: dateTime, modifiedDate: new Date()}
        
        Concert.update {concertID: skEvent.id},{$set: savingConcert}, {upsert: 1}, (err) ->
          if err?
            console.log "noting save error obj# #{concertIter} of #{ (concerts.length) - 1} for page # #{page}"
            console.log err, savingConcert
          if concertIter == concerts.length - 1
            callback null, page
  
  getConcertsNearLocation = (location, callback) -> #callback (err, concerts)
    radialKM = 1 * 1/6378 #in radial coord km/radiusEarth *ONLY WORKS ON EARTH*
    if location?
      query = { "location" : { $nearSphere : location, $maxDistance : radialKM * 5 }}
      Area.findOne query, (err, area) =>
        if err?
          console.log "error on area location lookup #{err} for query #{query}"
          callback err, null
          return
        if area? == false || area.concertsLastUpdated? == false || new Date().getTime() - area.concertsLastUpdated.getTime() > 1000*60*60*24
          metroAreaIDsAtLocation location, (error, firstArea, metroIDs) =>
            console.log "got #{metroIDs?.length} metro ids at loc with error #{error} and firstArea #{firstArea}"
            console.log metroIDs
            if metroIDs?.length > 0 && firstArea? == true
              updateConcertsWithMetroAreaIDs metroIDs, location, (err) =>
                console.log "did update metroAreaIDs with err #{err}"
                areaInfo = {concertsLastUpdated: new Date(), location: location, displayName: firstArea.displayName}
                criteria = { "location" : { $nearSphere : location, $maxDistance : radialKM * 5 }}
                #find the nearest 'area' and set it as updated, if it's within 5km, otherwise create one
                Area.update criteria, {$set: areaInfo},{upsert: 1}, (err) ->
                  if err?
                    returnErr = "error #{err} updating area #{area}"
                    callback returnErr
                  else
                    console.log "updated area, now recursion for get concerts"
                    getConcertsNearLocation location, callback
            else
              callback "no metroArea at location coord"
        else
          futureDate = new Date (new Date().getTime()+24*60*60*1000 * 7)
          pastDate = new Date (new Date().getTime()+-6*60*60*1000)
          Concert.find {"venue.location": {$nearSphere: location, $maxDistance: radialKM * 50}, startDateTime: {$gt: pastDate, $lt: futureDate}}, {feedItems: 0}, {limit:10000, sort: {startDateTime: 1}}, (err, concerts) =>
            console.log "this week concert count #{concerts?.length} and error #{err}"
            if concerts?.length > 200
              callback err, concerts
            else
              Concert.find {"venue.location": {$nearSphere: location, $maxDistance: radialKM * 50}, startDateTime: {$gt: pastDate}}, {feedItems: 0}, {limit:200, sort: {startDateTime: 1}}, (err, locationConcerts) =>
                console.log "all time concert count (max 200) #{locationConcerts?.length} and error #{err}"
                returnConcerts = locationConcerts?.concat(concerts).unique()
                callback err, returnConcerts

  updateConcertsWithMetroAreaIDs = (areaIDs, updateCentralLocation, callback) -> #callback (err)
    completionFunction = (metroAreaID, iterator, areaIDs,  theCallback) ->
      console.log "finished updating concerts for ##{iterator} of #{areaIDs.length} metroAreaIDs #{metroAreaID} @ #{new Date()}"
      if iterator == areaIDs.length
        console.log "last metroarea #{metroAreaID} updated"
        theCallback null
    iterator = 0
    for metroAreaID in areaIDs
      iterator = iterator+ 1
      do (metroAreaID, iterator) ->
        console.log "Updating concerts for metroAreaID #{metroAreaID} beginning #{new Date()}", metroAreaID
        requestURL = "https://api.songkick.com/api/3.0/metro_areas/#{metroAreaID}/calendar.json?apikey=B7tlwR9tyOXNG2qw"
        console.log requestURL
        request requestURL, (error, response, body) ->
          if response.statusCode == 200
            resObjects = JSON.parse body
            resPage = resObjects.resultsPage
            resCount =  resPage.totalEntries
            resPages = Math.ceil (resCount / resPage.perPage) #page 1 is first page, not zero.
            console.log resCount, resPage.totalEntries, resPages
            console.log "beginning fetch/integration of #{resPages} pages for metroAreaID #{metroAreaID}"
            
            firstEvents = resObjects?.resultsPage?.results?.event

            if resPages > 1
              integrateEvents firstEvents, 1, updateCentralLocation, (error, page) ->
                console.log "integration error on page #{page} #{error}"
              
              for page in [2..resPages]
                do (page) =>
                  requestURL = "https://api.songkick.com/api/3.0/metro_areas/#{metroAreaID}/calendar.json?apikey=B7tlwR9tyOXNG2qw&page=#{page}"
                  console.log requestURL
                  request requestURL, (error, response, body) =>
                    pageIn = page
                    if response.statusCode == 200
                      resObjects = JSON.parse body
                      resPage = resObjects.resultsPage
                      events = resPage?.results?.event
                      console.log "#{events?.length} events to integrate for page #{pageIn}"
                      if page == resPages
                        integrateEvents events, resPages, updateCentralLocation, (error, page) ->
                          console.log "integrated page# #{page}"
                          if error?
                            console.log "integration error on page #{page} #{error}, metroAreaID #{metroAreaID} update aborted"
                          completionFunction metroAreaID, iterator, areaIDs,  callback
                      else
                        integrateEvents events, page, updateCentralLocation, (error, page) ->
                          if error?
                            console.log "integration error on page #{page} #{error}"
                        
            else if resPages == 1
              integrateEvents firstEvents, 1, updateCentralLocation, (error, page) ->
                if error?
                  console.log "integration error on page #{page} #{error}, metroAreaID #{metroAreaID} update aborted"
                completionFunction metroAreaID, iterator, areaIDs,  callback
            else #respages == 0
              retErr = "no concerts nearby for URL: #{requestURL}"
              console.log retErr
              completionFunction metroAreaID, iterator, areaIDs,  callback
          else
            retErr = "bad response for URL #{requestURL}"
            console.log retErr
            completionFunction metroAreaID, iterator, areaIDs,  callback
 
  #gets all songkick metro ids at location
  metroAreaIDsAtLocation = (location, callback) -> #callback (error, firstArea, metroIDs)
    requestURL = "https://api.songkick.com/api/3.0/search/locations.json?apikey=B7tlwR9tyOXNG2qw&location=geo:#{location[1]},#{location[0]}"
    console.log requestURL
    request requestURL, (error,response,body) =>
      if response.statusCode == 200
        resObjects = JSON.parse body
        firstArea = resObjects?.resultsPage?.results?.location?[0]?.metroArea
        console.log firstArea
        if firstArea? == false
          callback "no area returned error"
          return
        metroIDs = []
        for itArea in resObjects?.resultsPage?.results?.location
          metroID = itArea?.metroArea?.id
          if metroID?
            metroIDs.push metroID
        metroIDs = metroIDs.unique()
        callback null, firstArea, metroIDs
      else
        callback "bad response for metroId lookup"

port = if process.env.PORT > 0 then process.env.PORT else 3000
swypApp.app.listen port
console.log "starting on port # #{port}"
