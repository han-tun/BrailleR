## Textify performs whisker rendering
## First parameter is a list of objects.  
## Second parameter is the name of a template file.
## Each object is rendered using the template of the same name 
## found within the template file.  Partial templates can also
## be present in the template file and will be used if needed.
.VItextify = function(x, template=system.file("whisker/VIdefault.txt", package="BrailleR")) {
  temp = read.csv(template,header=FALSE, as.is=TRUE)
  templates = as.list(gsub("\n", "", temp[,2]))
  names(templates) = temp[,1]
  result = list()
  for (i in 1:length(x)) {
    if (is.null(x[[i]])) {
      result[[i]] = character(0)
    } else {
      render = whisker::whisker.render(templates[names(x[i])], x[[i]], partials=templates)
      result[[i]] = as.vector(strsplit(render, "<br>", fixed=TRUE)[[1]])
    }
  }
  names(result) = names(x)
  return(result)
}

# This function adds flags to the VIstruct object that are only 
# required because of the limitations of mustache templating, as well
# as implementing the threshold for printing by setting "largecount" flags.
# Mustache can't check a field's value, only whether it's present or not.
# So flags are either set to true or not included at all
.VIpreprocess = function(x, threshold=10) {
  if (is.null(x))
    return(NULL)
  if (x$npanels == 1) 
    x$singlepanel = TRUE
  if (x$nlayers == 1) 
    x$singlelayer = TRUE
  if (length(x$panelrows) == 0) 
    x$singlerow = TRUE   
  if (length(x$panelcols) == 0) 
    x$singlecol = TRUE
  if (length(x$panelrows) > 0 && length(x$panelcols) > 0) 
    x$panelgrid = TRUE
  # If samescale then axis labels are at top level
  if (!is.null(x$xaxis$xticklabels))
    x$xaxis$xtickitems = .listifyVars(list(label=x$xaxis$xticklabels))
  if (!is.null(x$yaxis$yticklabels))
    x$yaxis$ytickitems = .listifyVars(list(label=x$yaxis$yticklabels))

  for (legendi in 1:length(x$legends)) {
    if (!is.null(x$legends[[legendi]]$scalelevels))
      x$legends[[legendi]]$scalelevelitems = 
        .listifyVars(list(level = x$legends[[legendi]]$scalelevels,
                          map = x$legends[[legendi]]$scalemaps))
  }
  for (paneli in 1:x$npanels) {
    # Othewise they're within the panels
    if (!is.null(x$panels[[paneli]]$xticklabels))
      x$panels[[paneli]]$xtickitems = .listifyVars(list(label=x$panels[[paneli]]$xticklabels))
    if (!is.null(x$panels[[paneli]]$yticklabels))
      x$panels[[paneli]]$ytickitems = .listifyVars(list(label=x$panels[[paneli]]$yticklabels))
    for (layeri in 1:x$nlayers) {
      layer = x$panels[[paneli]]$panellayers[[layeri]]
      typeflag = paste0("type",layer$type)
      layer[[typeflag]] = TRUE
      n = layer$n
      if (!is.null(n)) {
        if (n > 1) 
          layer$s = TRUE
        if (n > threshold) {
          layer$largecount = TRUE
        } else {
          if (layer$type == "line") {  # Lines are special, items are within groups
            for (i in 1:length(layer$lines)) {
              layer$lines[[i]]$linenum = i
              npoints = nrow(layer$lines[[i]]$scaledata)
              layer$lines[[i]]$npoints = npoints
              if (npoints > threshold)
                layer$lines[[i]]$largecount = TRUE
              else 
                layer$lines[[i]]$items = .listifyVars(layer$lines[[i]]$scaledata)
            }
          }
          else {
            layer$items = .listifyVars(layer$scaledata)
          }
        }
      }
      x$panels[[paneli]]$panellayers[[layeri]] = layer
    }
  }
  return(x)
}

# This function will convert vectors into lists for mustache
# Takes a named list of vectors, result is a list of lists
# Also adds item numbers and separator
# e.g. converts list(x=c(1,2),y=c(3,4)) into 
#     list(list(itemnum=1,x=1,y=3,sep=" and "),list(itemnum=2,x=2,y=4,sep=""))
# This code isn't efficient, but hopefully we aren't printing a huge number of points
.listifyVars = function(varlist) {
  itemlist = list()
  for (i in seq_along(varlist[[1]])) {  # Assumes all varlists are the same length
    item = list()
    for (j in seq_along(varlist)) {
      item$itemnum = i
      var = varlist[[j]]
      name = names(varlist)[j]
      item[[name]] = .cleanPrint(var[i])
    }
    len = length(varlist[[1]])
    # Separator, to allow whisker template to create and-separated lists
    if (i == len)
      item[["sep"]] = ""
    else if (i == len - 1)
      item[["sep"]] = " and "
    else
      item[["sep"]] = ", "
    itemlist[[i]] = item
  }
  return(itemlist)
}

# For now, limit all values printed to 2 decimal places.  Should do something smarter -- what does
# ggplot itself do?
.cleanPrint = function(x) {
  if (is.numeric(x))
    return(round(x,2))
  else
    return(x)
}

### Print function for the object created by VI.ggplot
### Prints the text component of the object
print.VIgraph = function(x, ...) {
  cat(x$text, sep="\n")
  invisible(x)
}

# Small helper function - builds list excluding items that are null or length 0
.VIlist = function(...) {
  l = list(...)
  l[(lapply(l,length) > 0)] 
}

sort.VIgraph <- function(x, decreasing = FALSE, by="x", ...) {
  if (!by %in% c("x", "y")) {
    message('Valid by parameters are "x" or "y".')
    return(x)    # Return unchanged
  }
  VIgg = x$VIgg
  for (i in 1:VIgg$npanels) {
    for (j in 1:VIgg$nlayers) {
      if (VIgg$panels[[i]]$panellayers[[j]]$type != "point") {
        message("Sorting is only supported on plots of type 'point'")
        return(x) # Return unchanged
      }
      df = VIgg$panel[[i]]$panellayers[[j]]$scaledata
      VIgg$panels[[i]]$panellayers[[j]] = within(VIgg$panels[[i]]$panellayers[[j]],
      {
        sortorder = order(if (by=="x") scaledata$x else scaledata$y, decreasing=decreasing)
        scaledata = scaledata[sortorder,]
      })
    }
  }
  text = .VItextify(list(VIgg=.VIpreprocess(VIgg, x$threshold)), x$template)[[1]]
  VIgraph = list(VIgg=VIgg, text=text, threshold=x$threshold, template=x$template)
  class(VIgraph) = "VIgraph"
  return(VIgraph)
}

grep <- function(pattern, x, ...) {
  ## Dispatch on 'x' rather than 'pattern' !!!
  UseMethod("grep", x)
}

grep.default <- function(pattern, x, ignore.case = FALSE, perl = FALSE, value = FALSE, fixed = FALSE, useBytes = FALSE, invert = FALSE, ...) {
  base::grep(pattern, x, ignore.case, perl, value, fixed, useBytes, invert)
}

# Returns the VIgraph object with the text trimmed down to only those rows
# containing the specified pattern.  Passes extra parameters on to grepl.
# Note that only the text portion of the VIgraph is modified; the complete
# VIgg structure is still included
grep.VIgraph <- function(pattern, x, ...) {
  x$text = grep(pattern, x$text, value=TRUE, ...)
  x
}

gsub <- function(pattern, replacement, x, ...) {
  ## Dispatch on 'x' rather than 'pattern' !!!
  UseMethod("gsub", x)
}

gsub.default <-
  function(pattern, replacement, x,
           ignore.case = FALSE, perl = FALSE,
           fixed = FALSE, useBytes = FALSE, ...) {
    base::gsub(pattern, replacement, x, ignore.case, perl, 
               fixed, useBytes)
  }

gsub.VIgraph <- function(pattern, replacement, x, ...) {
  x$text = gsub(pattern, replacement, x$text, ...)
  x
}

# threshold specifies how many points, lines, etc will be explicitly listed.
# Greater numbers will be summarised (e.g. "is a set of 32 horizontal lines" vs
# "is a set of 3 horizontal lines at 5, 7.5, 10")
VI.ggplot = function(x, Describe=FALSE, threshold=10, template=system.file("whisker/VIdefault.txt", package="BrailleR"), ...) {
  VIstruct = .VIstruct.ggplot(x)
  text = .VItextify(list(VIgg=.VIpreprocess(VIstruct, threshold)), template)[[1]]
  VIgraph = list(VIgg=VIstruct, text=text, threshold=threshold, template=template)
  class(VIgraph) = "VIgraph"
  return(VIgraph)
}

# Builds the VIgg structure describing the graph
.VIstruct.ggplot = function(x) {
  xbuild = suppressMessages(ggplot_build(x))
  # If this is a plot we really can't deal with, say so now
  if (!(.getGGCoord(x, xbuild) %in% c("CoordCartesian", "CoordFixed"))) {
    message("VI cannot process ggplot objects with flipped or non-Cartesian coordinates")
    return(NULL)
  }
  title = .getGGTitle(x, xbuild)
  subtitle = .getGGSubtitle(x, xbuild)
  caption = .getGGCaption(x, xbuild)
  annotations = .VIlist(title=title, subtitle=subtitle, caption=caption)
  xlabel = .getGGXLab(x, xbuild)
  ylabel = .getGGYLab(x, xbuild)
  if (!.getGGScaleFree(x, xbuild)) {    # Can talk about axis ticks at top level unless scale_free
    samescale = TRUE
    xticklabels = .getGGXTicks(x, xbuild, 1)
    yticklabels = .getGGYTicks(x, xbuild, 1)
  } else {
    samescale = NULL
    xticklabels = NULL
    yticklabels = NULL
  }
  xaxis = .VIlist(xlabel=xlabel, xticklabels=xticklabels, samescale=samescale)
  yaxis = .VIlist(ylabel=ylabel, yticklabels=yticklabels, samescale=samescale)
  legends = .buildLegends(x, xbuild)
  panels = .buildPanels(x, xbuild)
  panelrows = as.list(.getGGFacetRows(x, xbuild))
  panelcols = as.list(.getGGFacetCols(x, xbuild))
  layerCount = .getGGLayerCount(x, xbuild);
  VIstruct = .VIlist(annotations=annotations, xaxis=xaxis, yaxis=yaxis, legends=legends, panels=panels,
                     npanels=length(panels), nlayers=layerCount, panelrows=panelrows, panelcols=panelcols, type="ggplot")
  class(VIstruct) = "VIstruct"
  return(VIstruct)
}

.buildLegends = function(x, xbuild) {
  legends = list()
  labels = .getGGGuideLabels(x, xbuild)
  names = names(labels)
  guides = .getGGGuides(x, xbuild)
  for (i in seq_along(labels)) {
    name = names[i]
    mapping = labels[[i]]
    scale = .getGGScale(x, xbuild, name)
    ## From ggplot2 3.0.0 can have x$labels without any corresponding
    ## xbuild$plot$scales
    if (is.null(scale))
      break;
    scalediscrete = if ("ScaleDiscrete" %in% class(scale)) TRUE
    hidden = if (.isGuideHidden(x, xbuild, name)) TRUE
    maplevels = data.frame(col1=scale$map(scale$range$range), stringsAsFactors=FALSE)
    colnames(maplevels) = name
    maplevels = .convertAes(maplevels)
    maplevels = maplevels[[name]]
    if (!is.null(scalediscrete)) {
      scalenlevels = length(scale$range$range)
      scalelevels = scale$range$range
      scalemaps = maplevels
      legend = .VIlist(aes=name, mapping=unname(mapping), scalediscrete=scalediscrete, 
                       scalenlevels=scalenlevels, scalelevels=scalelevels, 
                       scalemaps=scalemaps, hidden=hidden)
    } else {
      scalefrom = scale$range$range[1]
      scaleto = scale$range$range[2]
      scalemapfrom = maplevels[1]
      scalemapto = maplevels[2]
      legend = .VIlist(aes=name, mapping=unname(mapping), scalediscrete=scalediscrete, 
                       scalefrom=scalefrom, scaleto=scaleto, 
                       scalemapfrom=scalemapfrom, scalemapto=scalemapto, hidden=hidden)
    }
    legends[[i]] = legend
  }
  return(legends)
}

.buildPanels = function(x, xbuild) {
  f = .getGGFacetLayout(x, xbuild)
  panels = list()
  names = colnames(f)
  panelvars = names[which(!names %in% c("PANEL", "ROW", "COL", "SCALE_X", "SCALE_Y"))]
  for (i in seq_along(f$PANEL)) {
    panel = list()
    panel[["panelnum"]] = as.character(f$PANEL[i])
    panel[["row"]] = f$ROW[i]
    panel[["col"]] = f$COL[i]
    scalefree = .getGGScaleFree(x, xbuild)
    panel[["samescale"]] = if (!scalefree) TRUE      # Might want to move this into pre-processing step
    if (scalefree) { 
      panel[["xticklabels"]] = .getGGXTicks(x, xbuild, i)
      panel[["yticklabels"]] = .getGGYTicks(x, xbuild, i)
      panel[["xlabel"]] = .getGGXLab(x, xbuild) # Won't actually change over the panels
      panel[["ylabel"]] = .getGGYLab(x, xbuild) # But we still want to mention them

    }
    vars = list()
    for (j in seq_along(panelvars)) {
      vars[[j]] = list(varname=as.character(panelvars[j]), value=as.character(f[[i, panelvars[j]]]))
    }
    panel[["vars"]] = vars
    panel[["panellayers"]] = .buildLayers(x, xbuild, i)
    panels[[i]] = panel
  }
  return(panels)  
}

.buildLayers = function(x, xbuild, panel) {
  layerCount = .getGGLayerCount(x, xbuild)
  layers = list()
  for (layeri in 1:layerCount) {
    layeraes = .getGGLayerAes(x, xbuild, layeri)
    layer = .VIlist(layernum=layeri, layeraes=layeraes)
    layer$data =.getGGPlotData(x, xbuild, layeri, panel)
    if (length(layer$data$group) > 0 && max(layer$data$group) > 0)  # ungrouped data have group = -1 
      ngroups = length(unique(layer$data$group))
    else
      ngroups = 1
    layerClass = .getGGLayerType(x, xbuild, layeri)

    # HLINE
    if (layerClass == "GeomHline") {
      layer$type = "hline"
      # Discard lines that go outside the bounds of the plot,
      # as they won't be displayed
      cleandata = layer$data[!is.na(layer$data$yintercept),]
      layer$n = nrow(cleandata)
      map = .mapDataValues(x, xbuild, list("yintercept"), panel, list(yintercept=cleandata$yintercept))
      if (!is.null(map$badTransform)) {
        layer$badtransform = TRUE
        layer$transform = map$badTransform
      } 
      layer$scaledata = map$value
      # Also report on any aesthetic variables that vary across the layer
      layer = .addAesVars(x, xbuild, cleandata, layeri, layer, panel)

      # POINT
    } else if (layerClass == "GeomPoint") {
      layer$type = "point"
      # Mark as hidden points that go outside the bounds of the plot,
      # as they won't be displayed
      cleandata = layer$data[!is.na(layer$data$x) & !is.na(layer$data$y),]
      layer$n = nrow(cleandata)
      map = .mapDataValues(x, xbuild, list("x", "y"), panel, 
                           list(x=cleandata$x, y=cleandata$y))
      if (!is.null(map$badTransform)) {
        layer$badtransform = TRUE
        layer$transform = map$badTransform
      } 
      layer$scaledata = map$value
      # Also report on any aesthetic variables that vary across the layer
      layer = .addAesVars(x, xbuild, cleandata, layeri, layer, panel)


      # BAR
    } else if (layerClass == "GeomBar") {
      layer$type = "bar"
      # Discard bars that go outside the bounds of the plot,
      # as they won't be displayed
      cleandata = layer$data[!is.na(layer$data$xmin) & !is.na(layer$data$xmax),]
      # Recount rows
      layer$n = nrow(cleandata)
      map = .mapDataValues(x, xbuild, list("x", "ymin", "ymax"), panel, 
                           list(x=cleandata$x, ymin=cleandata$ymin, ymax=cleandata$ymax))
      if (!is.null(map$badTransform)) {
        layer$badtransform = TRUE
        layer$transform = map$badTransform
      } 
      layer$scaledata = map$value
      # If bar width varies then we should report xmin and xmax instead
      width = cleandata$xmax - cleandata$xmin
      if (max(width) - min(width) > .0001)   # allow for small rounding error
        layer$scaledata = cbind(layer$scaledata, xmin=cleandata$xmin, xmax=cleandata$xmax)
      # Also report on any aesthetic variables that vary across the layer
      layer = .addAesVars(x, xbuild, cleandata, layeri, layer, panel)

      # LINE
    } else if (layerClass == "GeomLine") {
      layer$type = "line"
      # Lines are funny - each item in the data is a point
      # The number of actual lines depends on the group parameter
      layer$n = ngroups
      # Y values of NA or past ylims create broken lines
      if (any(is.na(layer$data$y)))  
        layer$broken = TRUE
      # X values of NA or past xlims should just not be reported on
      # as they won't be displayed but the line will still be continuous
      cleandata = layer$data[!is.na(layer$data$x),]
      layer = .addLineAesLabels(x, xbuild, layeri, layer, panel)
      # Each group is a line which has its own information including its own scaledata
      layer$lines = list()
      for (groupi in unique(cleandata$group)) {
        line = list()
        groupdata = cleandata[cleandata$group == groupi,]
        groupx = groupdata$x
        groupy = groupdata$y
        map = .mapDataValues(x, xbuild, list("x","y"), panel, list(x=groupx, y=groupy))
        if (!is.null(map$badTransform)) {
          layer$badtransform = TRUE
          layer$transform = map$badTransform
        } 
        # Lines have a separate scaledata for each group
        line$scaledata = map$value
        line = .addLineAesVars(x, xbuild, line, layeri, groupdata, panel)
        layer$lines[[length(layer$lines) + 1]] = line
      }

      #BOXPLOT
    } else if (layerClass == "GeomBoxplot") {
      layer$type = "box"
      cleandata = layer$data   # No need for cleaning since this data is already aggregated
      layer$n = nrow(layer$data)
      nOutliers = sapply(cleandata$outliers,length)
      map = .mapDataValues(x, xbuild,list("x", "ymin", "lower", "middle", "upper", "ymax"), panel,
                           list(x=cleandata$x, ymin=cleandata$ymin, lower=cleandata$lower, 
                                middle=cleandata$middle, upper=cleandata$upper, 
                                ymax=cleandata$ymax))
      if (!is.null(map$badTransform)) {
        layer$badtransform = TRUE
        layer$transform = map$badTransform
      } 
      layer$scaledata = map$value
      layer$scaledata[["noutliers"]] = nOutliers
      # Might want to report high and low outliers separately?
      # Would like to include outlier detail as well.
      # scaledata is currently a list of vectors.  If we wanted to include outliers
      # within each boxes object for reporting, then boxes would need to become
      # a list of lists.

      # Also report on any aesthetic variables that vary across the layer
      layer = .addAesVars(x, xbuild, cleandata, layeri, layer, panel)

      # SMOOTH
    } else if (layerClass == "GeomSmooth") {
      layer$type = "smooth"
      layer$method = .getGGSmoothMethod(x, xbuild, layeri)
      layer$ci = if (.getGGSmoothSEflag(x, xbuild, layeri)) TRUE

      #U UNKNOWN
    } else {
      layer$type = "unknown"
    }
    layers[[layeri]] = layer  
  }
  return(layers)
}

.mapAesDataValues = function(x, xbuild, layer, varlist, valuelist) {
  transformed = list()
  for (var in varlist) {
    value = valuelist[[var]]
    scale = .getGGScale(x, xbuild, var)

    if (is.null(scale))   # No scale found
      next
    else if (("ScaleDiscrete" %in% class(scale))) { # Try to map back to levels
      match = match(value, scale$palette.cache)
      transformed[[var]] = scale$range$range[match]
    } else {  # Continuous scale - We can't currently map these
      next
    }
  }
  return(transformed)
}

# Converts positional data values back to their original scales -- converting factor
# variables back to their levels, and undoisng transforms
.mapDataValues = function(x, xbuild, varlist, panel, valuelist) {
  badTransform = NULL
  transformed = list()
  for (var in varlist) {
    value = valuelist[[var]]
    scale = .getGGPanelScale(x, xbuild, var, panel)

    if (is.null(scale))   # No scale - just return the stored value
      r = value
    else if (("ScaleDiscrete" %in% class(scale))) { # Try to map back to levels
      map = scale$range$range
      if (is.null(map))
        r = value
      else {
        mapping = as.character(map[value])
        if (length(mapping) != length(value))  # Can happen with jittered data
          r = value     # Something's gone wrong - bail
        else
          r = mapping
      }
    } else {  # Continuous scale - try to undo any transform
      if (is.null(scale$trans)) {   # No transform
        r = value
      } else if (is.null(scale$trans$inverse)) {
        badTransform = scale$trans$name
        r = value
      } else {
        r = scale$trans$inverse(value)
      }
    }
    transformed[[var]] = r
  }
  return(list(value=as.data.frame(transformed), badTransform=badTransform))
}

# Convert aesthetic values to something more friendly for the user
# Takes a dataframe and converts all of its columns if possible
# *** ONLY HANDLING LINETYPES AND SHAPES SO FAR - and not defaults 42, 22, ...
# Colours defined using roloc and related packages
.convertAes = function(values) {
  linetypes = c("0"="blank", "1"="solid", "2"="dashed",
                "3"="dotted", "4"="dotdash", "5"="longdash", "6"="twodash")
  shapes = c("open square", "open circle", "open triangle", "plus", "X", "open diamond", "downward triangle",
             "boxed X", "star", "crossed diamond", "circled plus", "six-pointed star", "boxed plus",
             "crossed circle", "boxed triangle", "solid square", "solid circle", "solid triangle",
             "solid diamond", "big solid circle", "small solid circle", "fillable circle", 
             "fillable square", "fillable diamond", "fillable triangle", "fillable downward triangle") 
  c = values
  for (col in seq_along(values)) {
    aes = names(values)[col]
    if (aes == "linetype") {
      c[,col] = ifelse(values[[col]] %in% names(linetypes),
                       linetypes[as.character(values[[col]])],
                       c[,col])  # If not found just return what we got
    } else if (aes == "shape") {
      c[,col] = ifelse(values[,col] %in% 1:25, shapes[values[,col]+1], c[,col])
    } else if (aes %in% c("colour", "fill")) {
      c[,col] = colourName(values[,col], ISCCNBScolours)
    }
  }
  return(c)  
}

.addLineAesVars = function(x, xbuild, line, layeri, groupdata, panel) {
  aesvars = .findVaryingAesthetics(x, xbuild, layeri)
  linedata = groupdata[,aesvars,drop=FALSE]
  nvals = sapply(linedata,function(x) length(unique(x)))
  nonconstantAes = aesvars[nvals > 1]
  for (aes in seq_along(nonconstantAes))
    line[[paste0(nonconstantAes[aes],"varying")]] = TRUE
  aesvars = aesvars[nvals == 1]
  aesvals = .convertAes(groupdata[1,aesvars,drop=FALSE])
  ## Use unconverted aesthetics for reverse lookup of mappings
  ## groupdata[1,aesvars,drop=FALSE] rather than aesvals[1,,drop=FALSE]
  aesmap = .mapAesDataValues(x, xbuild, layeri, aesvars,
                             groupdata[1,aesvars,drop=FALSE])
  line[aesvars] = aesvals
  if (length(aesmap) > 0) {
    names(aesmap) = paste0(names(aesmap), "map")
    line[names(aesmap)] = aesmap
  }
  return(line)
}

.addLineAesLabels = function(x, xbuild, layeri, layer, panel) {
  aesvars = .findVaryingAesthetics(x, xbuild, layeri)
  aeslabel = .getGGGuideLabels(x, xbuild)[aesvars]
  if (length(aeslabel)>0) {
    names(aeslabel) = paste0(names(aeslabel),"label")
    layer = append(layer, aeslabel)
  }
  return(layer)
}

.addAesVars = function(x, xbuild, data, layeri, layer, panel) {
  # panel is not currently used in this function
  aesvars = .findVaryingAesthetics(x, xbuild, layeri)
  aesvals = .convertAes(data[aesvars])
  aeslabel = .getGGGuideLabels(x, xbuild)[aesvars]
  if (length(aeslabel)>0) {
    names(aeslabel) = paste0(names(aeslabel),"label")
    layer = append(layer, aeslabel)
  }
  aesmap = .mapAesDataValues(x, xbuild, layeri, aesvars, data[aesvars])
  layer$scaledata = append(layer$scaledata, aesvals)
  if (length(aesmap) == 0) {
    layer$scaledata = cbind(layer$scaledata, aesvals)
  } else {
    names(aesmap) = paste0(names(aesmap), "map")
    layer$scaledata = cbind(layer$scaledata, aesvals, aesmap)
  }
  return(layer)
}
