# Interpretation of Compression Models
#
# Gregory Way 2018
#
# This script stores functions for visualizing the results of a
# TCGA classification analysis
#
# Usage:
# source("scripts/viz_util.R")

load_results <- function(results_path,
                         file_string = "classify_metrics",
                         process_output = FALSE,
                         uses_top_features = FALSE,
                         process_ensemble = FALSE,
                         process_all_features = FALSE) {

  require(dplyr)
  require(readr)

  # From the finalized results, load and process specific result files
  #
  # Arguments:
  # results_path - the file path to scan for specific results of the tcga classify
  #                pipeline performed, typically either cancer-type or mutation focused
  # file_string - a string indicating which type of data to load in.
  #               choices: "classify_metrics" or "coefficients"
  # process_output - boolean indicating if the output should be processed
  #                  before returning. If False, output list of combined raw files
  # uses_top_features - boolean if the data to load was precompiled by top features
  # process_ensemble - boolean if the data to process is an ensemble model

  # Setup column types for specific file strings
  if (file_string == "classify_metrics") {
    if (uses_top_features) {
      metric_cols <- readr::cols(
        .default = readr::col_character(),
        auroc = readr::col_double(),
        aupr = readr::col_double()
        )
    } else {
      if (process_all_features) {
        metric_cols <- readr::cols(
          .default = readr::col_character(),
          auroc = readr::col_double(),
          aupr = readr::col_double(),
          z_dim = readr::col_character(),
          seed = readr::col_character()
        )
      } else {
        metric_cols <- readr::cols(
          .default = readr::col_character(),
          auroc = readr::col_double(),
          aupr = readr::col_double(),
          z_dim = readr::col_integer(),
          seed = readr::col_character()
        )
      }
    }
  } else if (file_string == "coefficients") {
    if (uses_top_features) {
      metric_cols <- readr::cols(
        .default = readr::col_character(),
        weight = readr::col_double(),
        abs = readr::col_double()
        )
    } else {
      if (process_all_features) {
        metric_cols <- readr::cols(
          feature = readr::col_character(),
          weight = readr::col_double(),
          abs = readr::col_double(),
          signal = readr::col_character(),
          z_dim = readr::col_character(),
          seed = readr::col_character(),
          algorithm = readr::col_character(),
          gene = readr::col_character()
        )
      } else {
        metric_cols <- readr::cols(
          feature = readr::col_character(),
          weight = readr::col_double(),
          abs = readr::col_double(),
          signal = readr::col_character(),
          z_dim = readr::col_integer(),
          seed = readr::col_character(),
          algorithm = readr::col_character(),
          gene = readr::col_character()
        )
      }
    }
  } else {
    stop("specify `file_string` as `classify_metrics` or `coefficients`")
  }
  results <- list()
  raw_results <- list()
  for (results_file in list.files(results_path)) {
    results_dir <- file.path(results_path, results_file)
    results_files <- list.files(results_dir)
    metric_files <- results_files[grep(file_string, results_files)]
    for (file in metric_files) {
      metric_file <- file.path(results_dir, file)
      results_df <- readr::read_tsv(metric_file, col_types = metric_cols)
      if ((grepl("raw", file) |
           grepl("ensemble", file)) &
          (!grepl("all_features", file))) {
        raw_results[[file]] <- results_df
      } else {
        results[[file]] <- results_df
      }
    }
  }

  metrics_df <- dplyr::bind_rows(results)
  if (!process_all_features) {
    raw_metrics_df <- dplyr::bind_rows(raw_results)
  }

  # Process data for plotting
  if (!uses_top_features & !process_all_features) {
    metrics_df <- metrics_df %>%
      dplyr::mutate(z_dim =
                      factor(z_dim,
                             levels = sort(as.numeric(paste(unique(z_dim))))))
    if (process_ensemble) {
      raw_metrics_df <- raw_metrics_df %>%
        dplyr::mutate(z_dim =
                        factor(z_dim,
                               levels = sort(as.numeric(paste(unique(z_dim))))))
    }
    algorithm_levels <- c("pca", "ica", "nmf", "dae", "vae")
  } else {
    algorithm_levels <- c("pca", "ica", "nmf", "dae", "vae", "all")
  }
  
  if (!process_ensemble & !process_all_features) {
    metrics_df$algorithm <-
      factor(metrics_df$algorithm, levels = algorithm_levels)
    
    metrics_df$algorithm <- metrics_df$algorithm %>%
      dplyr::recode_factor("pca" = "PCA",
                           "ica" = "ICA",
                           "nmf" = "NMF",
                           "dae" = "DAE",
                           "vae" = "VAE")
  }

  if (file_string == "classify_metrics") {
    metrics_df <- metrics_df %>%
      dplyr::mutate(data_type =
                      factor(data_type, levels = c("train", "test", "cv")))
  }

  if (process_output) {
    return_obj <- process_results(df = metrics_df, raw_df = raw_metrics_df)
  } else {
    if (process_all_features) {
      return_obj <- metrics_df
    } else {
      return_obj <- list("metrics" = metrics_df,
                         "raw_metrics" = raw_metrics_df)
    }
  }

  return(return_obj)
}

process_results <- function(df, raw_df, data_type = "cv") {
  # Filter and arrange metrics for plotting input. Typically used only in the
  # load_results function
  #
  # Arguments:
  # df - a dataframe storing classification results. The data includes classification
  #      performance and identiying information for each specific model.
  # raw_df - a dataframe storing classification results for raw data
  # data_type - which datatype to focus on plotting
  #
  # Output:
  # A processed dataframe for plotting

  # Setup data
  data_df <- df %>% dplyr::filter(data_type == !!data_type)
  data_df$grouping_ <- paste0(data_df$gene_or_cancertype,
                              data_df$signal)

  # Subset raw data
  raw_data_df <- raw_df %>%
    dplyr::filter(data_type == !!data_type) %>%
    dplyr::select(auroc, aupr, gene_or_cancertype, signal)

  # Join Dataframes
  data_df <- data_df %>%
    dplyr::left_join(raw_data_df,
                     by = c("gene_or_cancertype", "signal"),
                     suffix = c("", "_raw"))

  # Define a sorting mechanism
  mean_performance_df <- data_df %>%
    dplyr::group_by(gene_or_cancertype, signal) %>%
    dplyr::mutate(mean_auroc = mean(auroc))

  mean_performance_df <- dplyr::as_data_frame(mean_performance_df)

  signal_df <- mean_performance_df %>%
    dplyr::filter(signal == "signal") %>%
    dplyr::select(gene_or_cancertype, mean_auroc)
  shuffled_df <- mean_performance_df %>%
    dplyr::filter(signal == "shuffled") %>%
    dplyr::select(gene_or_cancertype, mean_auroc)

  signal_df$difference <- signal_df$mean_auroc - shuffled_df$mean_auroc

  difference_df <- signal_df[!duplicated(signal_df),]
  difference_df <- difference_df %>% dplyr::arrange(desc(difference))

  # Order the gene or cancer-type factor by difference in mean AUROC
  data_df$gene_or_cancertype <-
    factor(data_df$gene_or_cancertype,
           levels = difference_df$gene_or_cancertype)

  return(data_df)
}

process_sparsity <- function(coef_df,
                             mut_df,
                             focus_genes,
                             data_type = "cv",
                             label_dim_cutoff = 20,
                             process_ensemble = FALSE,
                             process_all_features = FALSE) {
  # Given a dataframe of gene coefficients, process a column of percent zero
  #
  # Arguments:
  # coef_df - the coefficient dataframe of interest
  # mut_df - dataframe storing performance metrics of the specific models
  # focus_genes - a character vector of which genes to focus on
  # data_type - which datatype to subset (default = "cv")
  # label_dim_cutoff - int of dimension to label cutoff shape (default = 20)
  # process_ensemble - boolean if the data to process is an ensemble model
  # process_all_features - boolean if the data to process uses all features
  #
  # Output:
  # A processed dataframe with a percent zero calculation

  coef_df <- coef_df %>%
    dplyr::filter(gene %in% focus_genes)

  num_zero_df <- coef_df %>%
    dplyr::group_by(gene, signal, z_dim, seed, algorithm) %>%
    dplyr::summarize_at("weight", funs(sum(. == 0)))

  denom_df <- coef_df %>%
    dplyr::group_by(gene, signal, z_dim, seed, algorithm) %>%
    dplyr::summarise(num_features = n())

  num_zero_df <- num_zero_df %>%
    dplyr::full_join(denom_df, by = c("gene",
                                      "signal",
                                      "z_dim",
                                      "seed",
                                      "algorithm")) %>%
    dplyr::mutate(percent_zero = weight / num_features)

  if (process_ensemble) {
    num_zero_df$seed <- "ensemble"
  }
  
  if (process_all_features) {
    num_zero_df$seed <- "ensemble_all_features"
    num_zero_df$algorithm <- paste(num_zero_df$algorithm)
  }
  
  cv_metrics_df <- mut_df %>%
      dplyr::filter(data_type == !!data_type)
  
  sparsity_metric_df <-
    dplyr::left_join(num_zero_df,
                     cv_metrics_df,
                     by = c("gene" = "gene_or_cancertype",
                            "signal",
                            "seed",
                            "algorithm",
                            "z_dim")) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(gene = factor(gene, levels = focus_genes)) %>%
    dplyr::mutate(signal = factor(signal, levels = c("signal", "shuffled")))
  
  if (!process_all_features) {
    sparsity_metric_df <- sparsity_metric_df %>%
      dplyr::mutate(z_dim_shape = 
                      ifelse(as.numeric(paste(
                        sparsity_metric_df$z_dim
                      )) >= label_dim_cutoff,
                      paste0("z >= ", label_dim_cutoff),
                      paste0("z < ", label_dim_cutoff)))
  }

  return(sparsity_metric_df)
}

plot_mutation_figure <- function(df, auroc_or_aupr = "auroc") {
  # Plot mutation figure across compression algorithms, mutations, and real and
  # permuted data
  #
  # Arguments:
  # df - the dataframe storing the data to visualize
  # auroc_or_aupr - plot either area under ROC or PR curves
  #
  # Output:
  # A ggplot grob of the figure

  if (auroc_or_aupr == "auroc") {
    g <- ggplot(df, aes(x = z_dim,
                        y = auroc,
                        linetype = signal)) +
      geom_boxplot(outlier.size = 0.1,
                   lwd = 0.3) +
      geom_hline(aes(yintercept = auroc_raw, 
                     color = signal),
                 linetype = "dashed") +
      geom_hline(yintercept = 0.5,
                 color = "grey",
                 linetype = "dashed",
                 alpha = 0.8) +
      ylim(c(0.4, 1)) 
  } else {
    g <- ggplot(df, aes(x = z_dim,
                        y = aupr,
                        linetype = signal)) +
      geom_boxplot(outlier.size = 0.1,
                   lwd = 0.3) +
      geom_hline(aes(yintercept = aupr_raw, 
                     color = signal),
                 linetype = "dashed") +
      ylim(c(0, 1)) 
  }
  
  g <- g +
    stat_summary(fun.y = mean,
                 geom = "line",
                 aes(group = grouping_, color = signal)) +
    scale_color_manual(name = "Signal",
                       values = c("#d53e4f", "#3288bd"),
                       labels = c("signal" = "Real",
                                  "shuffled" = "Permuted")) +
    xlab("k Dimension") +
    ylab(toupper(auroc_or_aupr)) +
    facet_grid(algorithm ~ gene_or_cancertype) +
    theme_bw() +
    theme(axis.text.x = element_blank(),
          axis.text.y = element_text(size = 5),
          legend.position = "top",
          legend.text = element_text(size = 12),
          legend.key.size = unit(1, "lines"),
          strip.background = element_rect(colour = "black",
                                          fill = "#fdfff4")) +
    guides(linetype = "none")

  return(g)
}


plot_final_performance <- function(metrics_df, metric, genes, signal,
                                   data_type) {
  # Plot the final AUROC or AUPR of the trained model across dimensions,
  # algorithms, and training/testing/cross validation
  #
  # Arguments:
  # metrics_df - dataframe storing the final metrics across all models
  # metric - the specific metric to plot (either "auroc" or "aupr")
  # genes - a character vector of the specific genes to plot
  # signal - the specific signal to plot (either "signal" or "shuffled")
  # data_type - the specific data_type to plot (either "cv", "train", or "test)

  metrics_sub_df <- metrics_df %>%
    dplyr::filter(gene_or_cancertype %in% !!genes,
                  signal == !!signal,
                  data_type == !!data_type)

  if (metric == "auroc") {
    g <- ggplot(metrics_sub_df, aes(x = z_dim, y = auroc, fill = algorithm))
  } else {
    g <- ggplot(metrics_sub_df, aes(x = z_dim, y = aupr, fill = algorithm))
  }
  g <- g +
    scale_fill_manual(name = "Algorithm",
                      values = c("#e41a1c",
                                 "#377eb8",
                                 "#4daf4a",
                                 "#984ea3",
                                 "#ff7f00"),
                      labels = c("pca" = "PCA",
                                 "ica" = "ICA",
                                 "nmf" = "NMF",
                                 "dae" = "DAE",
                                 "vae" = "VAE")) +
    scale_color_manual(name = "Algorithm",
                       values = c("#e41a1c",
                                  "#377eb8",
                                  "#4daf4a",
                                  "#984ea3",
                                  "#ff7f00"),
                       labels = c("pca" = "PCA",
                                  "ica" = "ICA",
                                  "nmf" = "NMF",
                                  "dae" = "DAE",
                                  "vae" = "VAE")) +
    ylab(toupper(metric)) +
    xlab("K Dimensions") +
    geom_boxplot(outlier.size = 0.1, lwd = 0.3) +
    stat_summary(fun.y = mean,
                 geom = "line",
                 aes(group = algorithm, color = algorithm)) +
    facet_wrap( ~ gene_or_cancertype, ncol = 3) +
    theme_bw() +
    guides(fill = guide_legend("none")) +
    theme(axis.text.x = element_text(angle = 90, size = 6))

  return(g)
}

plot_performance_panels <- function(plot_a, plot_b, gene, shuffled = FALSE) {
  # Build a cowplot of performance metrics and save
  #
  # Arguments:
  # plot_a - a ggplot object of the first plot to visualize
  # plot_b - a ggplot object of the second plot to visualize
  # gene - a string indicating the gene to plot
  # shuffled - a string indicating if data is shuffled
  #
  # Output:
  # The ggplot object and saving the plot to file

  add_legend <- cowplot::get_legend(plot_a)

  feature_plot <- (
    cowplot::plot_grid(
      plot_a + theme(legend.position = "none"),
      plot_b + theme(legend.position = "none"),
      labels = c("A", "B"),
      nrow = 2
    )
  )

  if (shuffled) {
    title_label <- paste("Predicting", gene, "Activation - Shuffled")
    figure_file <- file.path("figures",
                             paste0(gene, "_performance_metrics_shuffled.png"))
  } else {
    title_label <- paste("Predicting", gene, "Activation")
    figure_file <- file.path("figures",
                             paste0(gene, "_performance_metrics.png"))
  }
  title <- cowplot::ggdraw() +
    cowplot::draw_label(
      title_label,
      fontface = "bold"
      )

  feature_plot <- cowplot::plot_grid(title,
                                     feature_plot,
                                     ncol = 1,
                                     rel_heights = c(0.04, 1))
  feature_plot <- cowplot::plot_grid(feature_plot,
                                     add_legend,
                                     rel_widths = c(3, 0.3))

  cowplot::save_plot(figure_file, feature_plot, base_aspect_ratio = 1.1,
                     base_height = 8, base_width = 10)

  return(feature_plot)
}

plot_top_features <- function(top_df, full_df, raw_df, auroc_or_aupr = "AUROC") {
  # Aggregate several different datatypes together to generate summary plot
  #
  # Arguments:
  # top_df - dataframe storing classification performance using top algorithms
  # full_df - dataframe storing classification performance for z = 200
  # raw_df - dataframe storing classification performance with raw RNAseq features
  # auroc_or_aupr - string indicating to plot AUROC or AUPR
  #
  # Output:
  # The ggplot object
  
  # First, subset the input data into different categories
  
  # Select the top 200 features only that were not randomly selected
  top_feature_df <- top_df %>%
      dplyr::filter(z_dim == "top_features: 200",
                    signal == "real")

  # Select the top 1 feature that were not randomly selected
  top_one_df <- top_df %>%
      dplyr::filter(z_dim == "top_features: 1",
                    signal == "real")

  # Select 200 features only that were randomly selected
  top_random_df <- top_df %>%
      dplyr::filter(z_dim == "top_features: 200",
                    signal == "randomized")

  # Now, setup plotting logic
  if (auroc_or_aupr == "AUROC") {
    g <- ggplot(top_feature_df,
                aes(x = algorithm,
                    fill = algorithm,
                    y = auroc))
  } else {
    g <- ggplot(top_feature_df,
                aes(x = algorithm,
                    fill = algorithm,
                    y = aupr))
  }
   g <- g +
    geom_bar(color = "black",
             stat = "identity",
             position = position_dodge()) +
    facet_grid(~ gene_or_cancertype) +
    scale_shape_manual(name = "Raw Data",
                       values = c(21, 24),
                       labels = c("signal" = "Real",
                                  "shuffled" = "Permuted")) +
    scale_fill_manual(name = "Algorithm",
                      values = c("#e41a1c",
                                 "#377eb8",
                                 "#4daf4a",
                                 "#984ea3",
                                 "#ff7f00",
                                 "grey25"),
                      labels = c("pca" = "PCA",
                                 "ica" = "ICA",
                                 "nmf" = "NMF",
                                 "dae" = "DAE",
                                 "vae" = "VAE",
                                 "all" = "ALL")) +
    scale_linetype_manual(name = "Raw Data",
                          values = c("solid", "dashed"),
                          labels = c("signal" = "Real",
                                     "shuffled" = "Permuted")) +
    xlab("Algorithm") +
    ylab(paste("CV", auroc_or_aupr)) +
    theme_bw() +
    theme(axis.text.x = element_blank(),
          legend.position = "right",
          legend.title = element_text(size = 10),
          legend.text = element_text(size = 9),
          legend.key.size = unit(1, "lines"),
          strip.background = element_rect(colour = "black",
                                          fill = "#fdfff4")) +
    guides(fill = guide_legend(order = 1),
           shape = guide_legend(override.aes = list(size = 0.25)))

  if (auroc_or_aupr == "AUROC") {
    g <- g +
      coord_cartesian(ylim = c(0.4, 1)) +
      geom_point(data = full_df,
                 fill = "grey20",
                 color = "white",
                 size = 1.5,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = mean_auroc,
                     shape = signal)) +
      geom_hline(data = raw_df,
                 aes(yintercept = auroc,
                     linetype = signal),
                 color = "black",
                 lwd = 0.5) +
      geom_point(data = top_one_df,
                 fill = "yellow",
                 color = "black",
                 shape = 24,
                 size = 1.2,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = auroc)) +
      geom_point(data = top_random_df,
                 fill = "lightblue",
                 color = "black",
                 shape = 25,
                 size = 1.2,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = auroc))
  } else {
    g <- g +
      coord_cartesian(ylim = c(0.2, 1)) +
      geom_point(data = full_df,
                 fill = "grey20",
                 color = "white",
                 size = 1.5,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = mean_aupr,
                     shape = signal)) +
      geom_hline(data = raw_df,
                 aes(yintercept = aupr,
                     linetype = signal),
                 color = "black",
                 lwd = 0.5) +
      geom_point(data = top_one_df,
                 fill = "yellow",
                 color = "black",
                 shape = 25,
                 size = 1.2,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = aupr)) +
      geom_point(data = top_random_df,
                 fill = "lightblue",
                 color = "black",
                 shape = 23,
                 size = 1.2,
                 alpha = 0.8,
                 aes(x = algorithm,
                     y = aupr))
  }
  return(g)
}

process_delta_auc <- function(summary_df,
                              seed,
                              auroc_or_aupr = "auroc") {
  # Perform a series of dplyr steps and extract delta auroc between signal and
  # permuted data across algorithm, gene_or_cancertype, and z dimension
  #
  # Arguments:
  # summary_df - dataframe with mutation or cancertype performance
  # seed - a string of the seed to subset (we only need one)
  # auroc_or_aupr - string indicating to process AUROC or AUPR
  #
  # Output:
  # A processed dataframe
  
  # Process summary depending on auroc or aupr
  if (auroc_or_aupr == "auroc") {
    summary_df <- summary_df %>%
      dplyr::group_by(z_dim, algorithm, signal, gene_or_cancertype) %>%
      dplyr::mutate(avg_auc = mean(auroc))
  } else {
    summary_df <- summary_df %>%
      dplyr::group_by(z_dim, algorithm, signal, gene_or_cancertype) %>%
      dplyr::mutate(avg_auc = mean(aupr))
  }

  summary_df <- summary_df %>%
    dplyr::filter(seed == !!seed) %>%
    dplyr::arrange(z_dim, seed, algorithm, gene_or_cancertype) %>%
    dplyr::ungroup()
  
  signal_df <- summary_df %>% dplyr::filter(signal == 'signal')
  permuted_df <- summary_df %>% dplyr::filter(signal != 'signal')
  
  signal_df <- signal_df %>%
    dplyr::mutate(delta_auc = signal_df$avg_auc - permuted_df$avg_auc) %>%
    dplyr::group_by(algorithm, gene_or_cancertype) %>%
    dplyr::arrange(z_dim, .by_group = TRUE) %>%
    dplyr::mutate(auc_k_diff = delta_auc -
                    dplyr::lag(delta_auc,
                               default = dplyr::first(delta_auc))) %>%
    dplyr::group_by(z_dim, algorithm) %>%
    dplyr::mutate(mean_delta_auc = mean(delta_auc),
                  sd_delta_auc = sd(delta_auc)) %>%
    dplyr::ungroup()
  
  signal_df$grouping_ <- paste(signal_df$grouping_, signal_df$algorithm)
  
  return(signal_df)
  
}

plot_delta_auc_simple <- function(plot_df,
                                  plot_title,
                                  auroc_or_aupr = "auroc",
                                  plot_ensemble = TRUE,
                                  plot_all_features = FALSE,
                                  all_feature_df = "none") {
  # Plot the delta AUC across k dimension
  #
  # Arguments:
  # plot_df - Dataframe to extract plotting info from
  # plot_title - string indicating what to name the title of plot
  # auroc_or_aupr - string indicating what to label x axis
  # plot_ensemble - to determine if the plot should be an ensemble model
  # plot_all_features - boolean if plotting value of all features
  # all_feature_df - if plot_all_features, then plot this value
  #
  # Returns:
  # a ggplot2 object to save downstream

  if (plot_ensemble) {
    scale_colors <- c(
      "PCA" = "#e41a1c",
      "ICA" = "#377eb8",
      "NMF" = "#4daf4a",
      "DAE" = "#984ea3",
      "VAE" = "#ff7f00",
      "Model Ensemble" = "brown",
      "VAE Ensemble" = "grey50"
      )
    scale_labels <- c(
      "PCA" = "PCA",
      "ICA" = "ICA",
      "NMF" = "NMF",
      "DAE" = "DAE",
      "VAE" = "VAE",
      "Model Ensemble" = "Model Ensemble",
      "VAE Ensemble" = "VAE Ensemble"
    )
  } else {
    scale_colors <- c(
      "PCA" = "#e41a1c",
      "ICA" = "#377eb8",
      "NMF" = "#4daf4a",
      "DAE" = "#984ea3",
      "VAE" = "#ff7f00"
    )
    scale_labels <- c(
      "PCA" = "PCA",
      "ICA" = "ICA",
      "NMF" = "NMF",
      "DAE" = "DAE",
      "VAE" = "VAE"
    )
  }
  
  g <- ggplot(plot_df,
              aes(x = z_dim,
                  y = mean_delta_auc,
                  color = algorithm,
                  group = algorithm)) +
    geom_point(size = 0.15) +
    geom_line(lwd = 0.1) +
    scale_color_manual(name = "Algorithm",
                       values = scale_colors,
                       labels = scale_labels) +
    theme_bw() +
    ggtitle(plot_title) +
    ylab(expression(paste(Delta, " CV AUPR"))) +
    xlab("k Dimensions") +
    theme(axis.title.x = element_text(size = 6),
          axis.title.y = element_text(size = 6),
          axis.text.x = element_text(angle = 90, size = 4),
          axis.text.y = element_text(size = 5),
          plot.title = element_text(size = 8, hjust = 0.5),
          legend.text = element_text(size = 6),
          legend.title = element_text(size = 7),
          legend.key.size = unit(0.7, "lines"))
  
  if (plot_all_features) {
    g <- g + geom_hline(data = all_feature_df,
                        color = "navy",
                        lwd = 0.2,
                        aes(yintercept = mean_delta_auc),
                            linetype = "dashed")
  }
  return(g)
}
