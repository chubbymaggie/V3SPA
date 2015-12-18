    vespaControllers = angular.module('vespaControllers')

    vespaControllers.controller 'gibCtrl', ($scope, VespaLogger,
        IDEBackend, $timeout, $modal, PositionManager, RefPolicy, $q, SockJSService) ->

      comparisonPolicy = null
      comparisonRules = []
      $scope.input = 
        refpolicy: comparisonPolicy

      # The 'outstanding' attribute is truthy when a policy is being loaded
      $scope.status = SockJSService.status

      comparisonPolicyId = () ->
        if comparisonPolicy then comparisonPolicy.id else ""

Get the raw JSON

      fetch_raw = ->
        deferred = $q.defer()

        path_params = IDEBackend.write_filter_param([])

        req =
          domain: 'raw'
          request: 'parse'
          payload:
            policy: comparisonPolicy._id
            text: comparisonPolicy.documents.raw.text
            params: path_params.join("&")

        SockJSService.send req, (result)=>
          if result.error  # Service error

            $.growl(
              title: "Error"
              message: result.payload
            ,
              type: 'danger'
            )

            deferred.reject result.payload

          else  # valid response. Must parse
            comparisonPolicy.json = JSON.parse result.payload
            comparisonRules = comparisonPolicy.json.parameterized.rules

            deferred.resolve()

        return deferred.promise

Fetch the policy info (refpolicy) needed to get the raw JSON

      load_refpolicy = (id)=>
        if comparisonPolicy? and comparisonPolicy.id == id
          return

        deferred = @_deferred_load || $q.defer()

        req = 
          domain: 'refpolicy'
          request: 'get'
          payload: id

        SockJSService.send req, (data)=>
          if data.error?
            comparisonPolicy = null
            deferred.reject(comparisonPolicy)
          else
            comparisonPolicy = data.payload
            comparisonPolicy._id = comparisonPolicy._id.$oid

            deferred.resolve(comparisonPolicy)

        return deferred.promise
      
Enumerate the differences between the two policies

      find_differences2 = () =>
        uniqueQueryString = (field, sourceId) ->
          # "SELECT *, ARRAY({rule:rule}) as rules FROM ? a WHERE NOT EXISTS(SELECT * FROM ? b WHERE a.subject = b.subject) GROUP BY subject"
          "SELECT distinct [#{field}], ARRAY({rule:rule}) as rules, '[#{field}]' as type, '#{sourceId}' as policyid FROM ? a WHERE [#{field}] NOT IN (SELECT [#{field}] FROM ?) GROUP BY [#{field}]"

        intersectQueryString = (field) ->
          # Can use INTERSECT to get this result?
          # "SELECT distinct #{field} FROM ? WHERE #{field} IN (SELECT #{field} FROM ?)"
          "SELECT distinct [#{field}] FROM ?"

        # Get all in A, all in B, all in both
        # Set item.type=subject,object,perm,class
        # Set item.policy=A_ID,B_ID,both on each item
        # Group rules by each item and set item.rules=[rule_arr]

        #alasql('SELECT Phase, Step, Task, Val, ARRAY({Phase:Phase,Step:Step,Task:Task,Val:Val}) AS rules FROM ? GROUP BY Phase',[testData]);

        alasql("CREATE DATABASE diff; USE diff;")
        alasql("CREATE TABLE rules")
        alasql("CREATE TABLE comparison")

        alasql.tables.rules.data = $scope.rules
        alasql.tables.comparison.data = comparisonRules

        # db.compile('INSERT INTO one ($a,$b)');

        uniqueStmt = alasql.compile(
          "SELECT distinct [$field], ARRAY({rule:rule}) as rules, '[$field]' as type, '$sourceId' as policyid
          FROM rules WHERE [$field] NOT IN (SELECT [$field] FROM comparison) GROUP BY [$field]"
          ,
          "diff"
          )

        [
          {attr:"subject", arr:"subjNodes"},
          {attr:"object", arr:"objNodes"},
          {attr:"perms", arr:"permsNodes"},
          {attr:"class", arr:"classNodes"}
        ].forEach (type) ->
          #sourceRules = alasql(uniqueQueryString(type.attr, $scope.input.refpolicy.id), [$scope.rules, comparisonRules])
          #targetRules = alasql(uniqueQueryString(type.attr, comparisonPolicy.id), [comparisonRules, $scope.rules])
          sourceRules = uniqueStmt({field:type.attr,sourceId:$scope.input.refpolicy.id})
          targetRules = uniqueStmt({field:type.attr,sourceId:comparisonPolicy.id})
          intersectRules = []#alasql(intersectQueryString(type.attr), [comparisonRules, $scope.rules])
          graph[type.arr] = sourceRules.concat(targetRules).concat(intersectRules)

        console.log graph

      find_differences = () =>
        # Loop through each primary rule, getting the distinct subjects, objects, permissions, and classes
        # Give each of them the type, name, rules, and policy attributes
        # Set policy = primaryId
        nodesFromRules = (rules, policyid, nodes, links) ->
          rules.forEach (r) ->
            new_subject_node = new_object_node = new_class_node = new_perm_node = undefined

            # Find existing node if it exists
            curr_subject_node = _.findWhere(nodes, {type: "subject", name: r.subject})
            curr_object_node = _.findWhere(nodes, {type: "object", name: r.object})
            curr_class_node = _.findWhere(nodes, {type: "class", name: r.class})
            curr_perm_node = _.findWhere(nodes, {type: "perm", name: r.perm})

            # If node exists then update it, else create a new one
            if curr_subject_node
              curr_subject_node.rules.push r
            else
              new_subject_node = {type: "subject", name: r.subject, rules: [r], policy: policyid}
              nodes.push new_subject_node
            if curr_object_node
              curr_object_node.rules.push r
            else
              new_object_node = {type: "object", name: r.object, rules: [r], policy: policyid}
              nodes.push new_object_node
            if curr_class_node
              curr_class_node.rules.push r
            else
              new_class_node = {type: "class", name: r.class, rules: [r], policy: policyid}
              nodes.push new_class_node
            if curr_perm_node
              curr_perm_node.rules.push r
            else
              new_perm_node = {type: "perm", name: r.perm, rules: [r], policy: policyid}
              nodes.push new_perm_node

            # Generate links
            generateLink = (curr_source_node, curr_target_node, new_source_node, new_target_node, links) ->
              if curr_source_node and !curr_target_node
                links.push {source: curr_source_node, target: new_target_node, rules: [new_target_node.rules]}
              else if !curr_source_node and curr_target_node
                links.push {source: new_source_node, target: curr_target_node, rules: [new_source_node.rules]}
              else if !curr_source_node and !curr_target_node
                links.push {source: new_source_node, target: new_target_node, rules: [new_source_node.rules]}
              else
                l = _.findWhere links, {source: curr_source_node, target: curr_target_node}
                if l
                  l.rules.push r
                else
                  # Source and target were previously found in two separate rules
                  links.push {source: curr_source_node, target: curr_target_node, rules: [r]}

            generateLink(curr_perm_node, curr_object_node, new_perm_node, new_object_node, links)
            generateLink(curr_subject_node, curr_perm_node, new_subject_node, new_perm_node, links)
            generateLink(curr_object_node, curr_class_node, new_object_node, new_class_node, links)
            generateLink(curr_perm_node, curr_class_node, new_perm_node, new_class_node, links)

        graph.links.length = 0

        primaryNodes = []
        comparisonNodes = []
        nodesFromRules($scope.rules, IDEBackend.current_policy.id, primaryNodes, graph.links)
        nodesFromRules(comparisonRules, comparisonPolicyId(), comparisonNodes, graph.links)

        # Reconcile the two lists of nodes
        # Loop over the primary nodes: if in comparison nodes
        # - change "policy" to "both"
        # - push the comparison's rules onto the primary's (ignore duplicates)
        # - remove from comparisonNodes
        primaryNodes.forEach (node) ->
          comparisonNode = _.findWhere(comparisonNodes, {type: node.type, name: node.name})
          if comparisonNode
            node.rules = _.uniq node.rules.concat(comparisonNode.rules)
            node.policy = "both"
            comparisonNodes = _.without(comparisonNodes, comparisonNode)
            linkSource = _.where(graph.links, {source: comparisonNode})
            linkTarget = _.where(graph.links, {target: comparisonNode})
            if linkSource.length
              graph.links = _.difference(graph.links, linkSource)
            if linkTarget.length
              graph.links = _.difference(graph.links, linkTarget)

        allNodes = primaryNodes.concat comparisonNodes

        graph.subjNodes = allNodes.filter (d) -> d.type == "subject"
        graph.objNodes = allNodes.filter (d) -> d.type == "object"
        graph.classNodes = allNodes.filter (d) -> d.type == "class"
        graph.permNodes = allNodes.filter (d) -> d.type == "perm"

        linkScale.domain d3.extent(graph.links, (l) -> return l.rules.length)
        

      $scope.load = ->
        load_refpolicy($scope.input.refpolicy.id).then(fetch_raw).then(update)

      $scope.list_refpolicies = 
        query: (query)->
          promise = RefPolicy.list()
          promise.then(
            (policy_list)->
              dropdown = 
                results:  for d in policy_list
                  id: d._id.$oid
                  text: d.id
                  data: d

              query.callback(dropdown)
          )

      width = 300
      height = 500
      padding = 50
      radius = 5
      graph =
        links: []
        subjNodes: []
        objNodes: []
        classNodes: []
        permNodes: []
      color = d3.scale.category10()
      svg = d3.select("svg.gibview").select("g.viewer")
      subjSvg = svg.select("g.subjects").attr("transform", "translate(0,0)")
      permSvg = svg.select("g.permissions").attr("transform", "translate(#{width+padding},0)")
      objSvg = svg.select("g.objects").attr("transform", "translate(#{2*(width+padding)},-#{height/2})")
      classSvg = svg.select("g.classes").attr("transform", "translate(#{3*(width+padding)},0)")

      linkScale = d3.scale.linear()
        .range([1,2*radius])

      gridLayout = d3.layout.grid()
        .points()
        .size([width, height])

      textStyle =
        'text-anchor': "middle"
        'fill': "#ddd"
        'font-size': "56px"
      svg.select("g.labels").append("text")
        .attr "x", width / 2
        .attr "y", height / 2
        .style textStyle
        .text "subjects"
      svg.select("g.labels").append("text")
        .attr "x", (width + padding) + width / 2
        .attr "y", height / 2
        .style textStyle
        .text "permissions"
      svg.select("g.labels").append("text")
        .attr "x", 2 * (width + padding) + width / 2
        .attr "y", 0
        .style textStyle
        .text "objects"
      svg.select("g.labels").append("text")
        .attr "x", 3 * (width + padding) + width / 2
        .attr "y", height / 2
        .style textStyle
        .text "classes"

      $scope.update_view = (data) ->
        $scope.policy = IDEBackend.current_policy

        # If the policy has changed, need to update/remove the old visuals
        $scope.rules = if data.parameterized?.rules? then data.parameterized.rules else []

        update()

      update = () ->
        find_differences()

        [
          {nodes: graph.subjNodes, svg: subjSvg},
          {nodes: graph.objNodes, svg: objSvg},
          {nodes: graph.permNodes, svg: permSvg},
          {nodes: graph.classNodes, svg: classSvg}
        ].forEach (tuple) ->
          nodeMouseover = (d,i) ->
            linksToShow = []

            # Find all links associated with this node
            if d.type == "object"
              # Get links to permissions
              linksToShow = _.where graph.links, {target: d}
              # Get links to classes
              linksToShow = linksToShow.concat _.where graph.links, {source: d}
              # Get links from permissions to classes, if they are associated with this object
              linksToShow = linksToShow.concat _.filter graph.links, (link) ->
                return _.findWhere(linksToShow, {source: link.source}) and _.findWhere(linksToShow, {target: link.target})
              # Get links from subjects to permissions
              permRules = _.uniq(_.where($scope.rules.concat(comparisonRules), {object: d.name}), (d) -> return d.perm)
              linksToShow = linksToShow.concat _.filter graph.links, (link) -> return _.findWhere permRules, {perm: link.target.name}
            else if d.type == "subject"
              # Get links from permissions to objects and permissions to classes
              permRules = _.uniq(_.where($scope.rules.concat(comparisonRules), {subject: d.name}), (d) -> return d.perm)
              linksToShow = linksToShow.concat _.filter graph.links, (link) -> return _.findWhere permRules, {perm: link.source.name}
              # Get links from objects to classes
              linksToShow = linksToShow.concat _.filter graph.links, (link) ->
                return _.findWhere(linksToShow, {target: link.source}) and _.findWhere(linksToShow, {target: link.target})
              # Get links to permissions
              linksToShow = linksToShow.concat _.where graph.links, {source: d}
            else if d.type == "perm"
              # Get links to objects and classes
              linksToShow = _.where graph.links, {source: d}
              # Get links from objects to classes, if the they are associated with this permission
              linksToShow = linksToShow.concat _.filter graph.links, (link) ->
                return _.findWhere(linksToShow, {target: link.source}) and _.findWhere(linksToShow, {target: link.target})
              # Get links from subjects to this perm
              linksToShow = linksToShow.concat _.where graph.links, {target: d}
            else # this is d.type == "class"
              # Find all permissions and object types on this class
              linksToShow = _.where(graph.links, {target: d})
              # Get links from permissions to objects, if the they are associated with this class
              linksToShow = linksToShow.concat _.filter graph.links, (link) ->
                return _.findWhere(linksToShow, {source: link.source}) and _.findWhere(linksToShow, {source: link.target})
              # Find all subjects that have permissions on this class
              permRules = _.uniq(_.where($scope.rules.concat(comparisonRules), {class: d.name}), (d) -> return d.perm)
              linksToShow = linksToShow.concat _.filter graph.links, (link) -> return _.findWhere permRules, {perm: link.target.name}

            d3.selectAll linksToShow.map((link) -> ".l-#{link.source.type}-#{link.source.name}-#{link.target.type}-#{link.target.name}").join ","
              .style "display", ""

            uniqNodes = linksToShow.reduce((prev, l) ->
              prev.push l.source
              prev.push l.target
              return prev
            , [])
            
            d3.selectAll _.uniq(uniqNodes.map((n) -> return "text.t-#{n.type}-#{n.name}")).join(",")
              .style "display", ""
            d3.selectAll _.uniq(uniqNodes.map((n) -> return "g.node.t-#{n.type}-#{n.name}")).join(",")
              .each () -> @.parentNode.appendChild(@)

          nodeMouseout = (d,i) ->
            link.style "display", "none"
            d3.selectAll "g.node text"
              .style "display", "none"

          # Sort 
          tuple.nodes.sort (a,b) ->
            if (a.policy == IDEBackend.current_policy.id && a.policy != b.policy) || (a.policy == "both" && b.policy == comparisonPolicyId())
              return -1
            else if a.policy == b.policy
              return 0
            else
              return 1

          node = tuple.svg.selectAll ".node"
          
          # Clear the old nodes and redraw everything
          node.remove()

          node = tuple.svg.selectAll ".node"
            .data gridLayout(tuple.nodes)
            .attr "class", (d) -> "node t-#{d.type}-#{d.name}"

          nodeEnter = node.enter().append "g"
            .attr "class", (d) -> "node t-#{d.type}-#{d.name}"
            .attr "transform", (d) -> return "translate(#{d.x},#{d.y})"

          nodeEnter.append "text"
            .attr "class", (d) -> "node-label t-#{d.type}-#{d.name}"
            .attr "x", 0
            .attr "y", "-5px"
            .style "display", "none"
            .text (d) -> d.name

          nodeEnter.append "circle"
            .attr "r", radius
            .attr "cx", 0
            .attr "cy", 0
            .attr "class", (d) ->
              if d.policy == IDEBackend.current_policy.id
                return "diff-left"
              else if d.policy == comparisonPolicyId()
                return "diff-right"
            .on "mouseover", nodeMouseover
            .on "mouseout", nodeMouseout

          node.exit().remove()

        link = svg.select("g.links").selectAll ".link"

        # Clear the old links and redraw everything
        link.remove()

        link = svg.select("g.links").selectAll ".link"
          .data graph.links, (d,i) -> return "#{d.source.type}-#{d.source.name}-#{d.target.type}-#{d.target.name}"

        link.enter().append "line"
          .attr "class", (d) -> "link l-#{d.source.type}-#{d.source.name}-#{d.target.type}-#{d.target.name}"
          .style "stroke-width", (d) -> return d.rules.length
          .style "display", "none"
          .attr "x1", (d) ->
            offset = 0
            if d.source.type == "perm"
              offset = width + padding
            else if d.source.type == "object"
              offset = 2 * (width + padding)
            return d.source.x + offset
          .attr "y1", (d) -> return d.source.y - if d.source.type == "object" then height/2 else 0
          .attr "x2", (d) ->
            offset = width + padding
            if d.target.type == "object"
              offset = 2 * (width + padding)
            else if d.target.type == "class"
              offset = 3 * (width + padding)
            return d.target.x + offset
          .attr "y2", (d) -> return d.target.y - if d.target.type == "object" then height/2 else 0

        link.style "stroke-width", (d) -> return linkScale(d.rules.length)

        link.exit().remove()

Set up the viewport scroll

      positionMgr = PositionManager("tl.viewport::#{IDEBackend.current_policy._id}",
        {a: 0.7454701662063599, b: 0, c: 0, d: 0.7454701662063599, e: 200, f: 50}
      )

      svgPanZoom.init
        selector: '#surface svg'
        panEnabled: true
        zoomEnabled: true
        dragEnabled: false
        minZoom: 0.5
        maxZoom: 10
        onZoom: (scale, transform) ->
          positionMgr.update transform
        onPanComplete: (coords, transform) ->
          positionMgr.update transform

      $scope.$watch(
        () -> return (positionMgr.data)
        , 
        (newv, oldv) ->
          if not newv? or _.keys(newv).length == 0
            return
          g = svgPanZoom.getSVGViewport($("#surface svg")[0])
          svgPanZoom.set_transform(g, newv)
      )

      IDEBackend.add_hook "json_changed", $scope.update_view
      $scope.$on "$destroy", ->
        IDEBackend.unhook "json_changed", $scope.update_view

      start_data = IDEBackend.get_json()
      if start_data
        $scope.update_view(start_data)