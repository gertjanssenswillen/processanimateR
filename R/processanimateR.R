#' @title Animate cases on a process map
#'
#' @description A function for creating a SVG animation of an event log on a process map created by processmapR.
#' @param eventlog The event log object that should be animated
#' @param processmap The process map created with processmapR that the event log should be animated on,
#'  if not provided a standard process map will be generated by using processmapR::process_map.
#' @param animation_mode Whether to animate the cases according to their actual time of occurence ("absolute") or to start all cases at once ("relative").
#' @param animation_duration The overall duration of the animation, all times are scaled according to this overall duration.
#' @param token_size The event attribute (character) or alternatively a data frame with three columns (case, time, size) matching the case identifier of the supplied event log.
#'  The token size is scaled accordingly during the animation (default size is 4). You may use \code{\link{add_token_size}} to add a suitable attribute to the event log.
#' @param token_color The event attribute (character) or alternatively a data frame with three columns (case, time, color) matching the case identifier of the supplied event log.
#'  The token color is change accordingly during the animation (default color is orange). You may use \code{\link{add_token_color}} to add a suitable attribute to the event log.
#' @param token_image The event attribute (character) or alternatively a data frame with three columns (case, time, image) matching the case identifier of the supplied event log.
#'  The token image is change accordingly during the animation (by default a SVG shape is used).
#' @param width The width of the htmlwidget.
#' @param height The height of the htmlwidget.
#'
#' @examples
#' \dontrun{
#' library(eventdataR)
#' data(patients)
#'
#' # Animate the process with default options (absolute time and 60s)
#' animate_process(patients)
#'
#' # Change default token sizes
#' animate_process(patients, token_size = 2)
#'
#' # Change default token color
#' animate_process(patients, token_color = "red")
#'
#' # Change default token image
#' animate_process(patients, token_image = "https://upload.wikimedia.org/wikipedia/en/5/5f/Pacman.gif")
#'
#' # Change token color based on a numeric attribute, here the nonsensical 'time' of an event
#' animate_process(add_token_color(patients, "time", "color"), token_color = "color")
#'
#' # Change token color based on a factor attribute
#' animate_process(add_token_color(patients, "employee", "color",
#'                 color_mapping = scales::col_factor("Set3", patients$employee)),
#'                 token_color = "color")
#'
#' # Change token_color based on colors in a second data frame
#' data(sepsis)
#' # Extract only the lacticacid measurements
#' lactic <- sepsis %>%
#'     mutate(lacticacid = as.numeric(lacticacid)) %>%
#'     filter_activity(c("LacticAcid")) %>%
#'     as.data.frame() %>%
#'     select("case" = case_id, "time" =  timestamp, lacticacid)
#' # Create a numeric color scale
#' cscale <- scales::col_numeric("Oranges", lactic$lacticacid , na.color = "white")
#' # Create colors data frame for animate_process
#' lacticColors <- lactic %>%
#'     mutate(color = cscale(lacticacid))
#' sepsisBase <- sepsis %>%
#'     filter_activity(c("LacticAcid", "CRP", "Leucocytes", "Return ER",
#'                       "IV Liquid", "IV Antibiotics"), reverse = T) %>%
#'     filter_trace_frequency(percentage = 0.95)
#' animate_process(sepsisBase, token_color = lacticColors, animation_mode = "relative",
#'                 animation_duration = 600)
#' }
#'
#'
#' @author Felix Mannhardt <felix.mannhardt@sintef.no> (SINTEF Technology and Society)
#' @seealso processmapR:process_map
#'
#' @import dplyr
#' @import bupaR
#' @import processmapR
#' @importFrom magrittr %>%
#' @importFrom rlang :=
#'
#' @export
animate_process <- function(eventlog,
                            processmap = NULL,
                            animation_mode = "absolute",
                            animation_duration = 60,
                            token_size = NULL,
                            token_color = NULL,
                            token_image = NULL,
                            width = NULL,
                            height = NULL) {
  #make CRAN happy
  case_start <- log_end <- start_time <- end_time <- next_end_time <- case <- case_end <- log_start <- log_duration <- NULL
  case_duration <- from_id <- to_id <- next_start_time <- NULL

  if (is.null(processmap)) {
    # standard process map
    processmap <- process_map(eventlog, render = F)
  }

  graph <- DiagrammeR::render_graph(processmap, width = width, height = height)
  # get the DOT source for later rendering by vis.js
  diagram <- graph$x$diagram

  precedence <- attr(processmap, "base_precedence") %>%
    mutate_at(vars(start_time, end_time, next_start_time, next_end_time), as.numeric, units = "secs")

  cases <- precedence %>%
    group_by(case) %>%
    filter(!is.na(case)) %>%
    summarise(case_start = min(start_time, na.rm = T),
              case_end = max(end_time, na.rm = T)) %>%
    mutate(case_duration = case_end - case_start) %>%
    ungroup() %>%
    mutate(log_start = min(case_start, na.rm = T),
           log_end = max(case_end, na.rm = T),
           log_duration = log_end - log_start)

  # determine animation factor based on requested duration
  if (animation_mode == "absolute") {
    animation_factor = cases %>% pull(log_duration) %>% first() / animation_duration
  } else {
    animation_factor = cases %>% pull(case_duration) %>% max(na.rm = T) / animation_duration
  }

  sizes <- generate_animation_attribute(eventlog, "size", token_size, 6)
  sizes <- transform_time(sizes, "size", cases, animation_mode, animation_factor)

  colors <- generate_animation_attribute(eventlog, "color", token_color, "white")
  colors <- transform_time(colors, "color", cases, animation_mode, animation_factor)

  images <- generate_animation_attribute(eventlog, "image", token_image, NA)
  images <- transform_time(images, "image", cases, animation_mode, animation_factor)

  tokens <- generate_tokens(cases, precedence, processmap, animation_mode, animation_factor)
  start_activity <- tokens %>% slice(1) %>% pull(from_id)
  end_activity <- tokens %>% slice(n()) %>% pull(to_id)
  cases <- tokens %>% distinct(case) %>% pull(case)

  settings <- list()
  x <- list(
    diagram = diagram,
    tokens = tokens,
    sizes = sizes,
    colors = colors,
    cases = cases,
    images = images,
    shape = "circle", #TODO make configureable
    start_activity = start_activity,
    end_activity = end_activity,
    settings = settings
  )

  htmlwidgets::createWidget(name = "processanimateR", x = x,
                            width = width, height = height,
                            sizingPolicy = htmlwidgets::sizingPolicy(
                              defaultWidth = 800,
                              defaultHeight = 600,
                              browser.fill = TRUE
                            ))
}

#' @title Create a process animation output element
#' @description Renders a renderProcessanimater within an application page
#' @param outputId output variable to read the animation from
#' @param width The desired width of the SVG
#' @param height The desired height of the SVG
#'
#' @export
processanimaterOutput <- function(outputId, width = NULL, height = NULL) {
  htmlwidgets::shinyWidgetOutput(outputId = outputId,
                                 name = "processanimateR",
                                 inline = F,
                                 width = width, height = height,
                                 package = "processanimateR")
}

#' @title Renders process animation output
#' @description Renders a SVG process animation suitable to be used by processanimaterOutput
#' @param expr The expression generating a process animation (animate_process)
#' @param env The environment in which to evaluate expr
#' @param quoted Is expr a quoted expression (with quote())? This is useful if you want to save an expression in a variable.
#'
#' @export
renderProcessanimater <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) { expr <- substitute(expr) } # force quoted
  htmlwidgets::shinyRenderWidget(expr, processanimaterOutput, env, quoted = TRUE)
}

#
# Private helper functions
#

generate_tokens <- function(cases, precedence, processmap, animation_mode, animation_factor) {

  case <- end_time <- next_end_time <- next_start_time <- case_start <- token_duration <- NULL
  min_order <- token_start <- activity_duration <- token_end <- from_id <- to_id <- case_duration <- NULL

  tokens <- precedence %>%
    left_join(cases, by = c("case")) %>%
    left_join(processmap$edges_df, by = c("from_id" = "from", "to_id" = "to")) %>%
    filter(!is.na(id) & !is.na(case))

  # SVG animations seem to not like events starting at the same time caused by 0s durations
  EPSILON = 0.00001

  if (animation_mode == "absolute") {
    log_start <- min(cases$case_start, na.rm = T)
    tokens <- mutate(tokens,
                     token_start = (end_time - log_start) / animation_factor,
                     token_duration = (next_start_time - end_time) / animation_factor,
                     activity_duration = EPSILON + pmax(0, (next_end_time - next_start_time) / animation_factor))
  } else {
    tokens <- mutate(tokens,
                     token_start = (end_time - case_start) / animation_factor,
                     token_duration = (next_start_time - end_time) / animation_factor,
                     activity_duration = EPSILON + pmax(0, (next_end_time - next_start_time) / animation_factor))
  }

  tokens <- tokens %>%
    # Filter all negative durations caused by parallelism (TODO, deal with it in a better way)
    # Also, SMIL does not like 0 duration animateMotion
    filter(token_duration >= 0) %>%
    group_by(case) %>%
    # Ensure start times are not overlapping SMIL does not fancy this
    arrange(min_order) %>%
    # Add small delta for activities with same start time
    mutate(token_start = token_start + ((row_number(token_start) - min_rank(token_start)) * EPSILON)) %>%
    # Ensure consecutive start times
    mutate(token_end = min(token_start) + cumsum(token_duration + activity_duration) + EPSILON) %>%
    mutate(token_start = lag(token_end, default = min(token_start))) %>%
    # Adjust case duration
    mutate(case_duration = max(token_end)) %>%
    ungroup()

  tokens %>%
    select(case,
           edge_id = id,
           from_id,
           to_id,
           token_start,
           token_duration,
           activity_duration,
           case_duration)

}

generate_animation_attribute <- function(eventlog, attributeName, value, default) {
  attribute <- rlang::sym(attributeName)
  # standard token size
  if (is.null(value)) {
    eventlog %>%
      as.data.frame() %>%
      select(case = !!case_id_(eventlog),
             time = !!timestamp_(eventlog)) %>%
      mutate(!!attribute := default)
  } else if (is.data.frame(value)) {
    stopifnot(c("case", "time", attributeName) %in% colnames(value))
    value
  } else if (value %in% colnames(eventlog)) {
    eventlog %>%
      as.data.frame() %>%
      select(case = !!case_id_(eventlog),
             time = !!timestamp_(eventlog),
             !!rlang::sym(value)) %>%
      mutate(!!attribute := !!rlang::sym(value))
  } else {
    eventlog %>%
      as.data.frame() %>%
      select(case = !!case_id_(eventlog),
             time = !!timestamp_(eventlog)) %>%
      mutate(!!attribute := value)
  }
}

transform_time <- function(data, col, cases, animation_mode, animation_factor) {

  .order <- time <- case <- log_start <- case_start <- NULL

  col <- rlang::sym(col)
  data <- data %>%
    group_by(case) %>%
    filter(row_number(!!col) == 1 | lag(!!col) != !!col) %>%
    left_join(cases, by = "case")

  if (animation_mode == "absolute") {
    data <- data %>%
      mutate(time = as.numeric(time - log_start, units = "secs") / animation_factor) %>%
      select(case, time, !!col)
  } else {
    col <- data %>%
      mutate(time = as.numeric(time - case_start, units = "secs") / animation_factor) %>%
      select(case, time, !!col)
  }

}

#
# Some functions copied from processmapR that were not exported (MIT)
# TODO ask upstream package to export a utility method

# Utility functions
# https://github.com/gertjanssenswillen/processmapR/blob/master/R/utils.R

case_id_ <- function(eventlog) rlang::sym(case_id(eventlog))
activity_id_ <- function(eventlog) rlang::sym(activity_id(eventlog))
activity_instance_id_ <- function(eventlog) rlang::sym(activity_instance_id(eventlog))
resource_id_ <- function(eventlog) rlang::sym(resource_id(eventlog))
timestamp_ <- function(eventlog) rlang::sym(timestamp(eventlog))
lifecycle_id_ <- function(eventlog) rlang::sym(lifecycle_id(eventlog))


