# Functions useful for summarization of data generated by 
# Can_Cenik_lab.Ian_Hoskins.bioinfo.analysis.variant_caller.VariantCaller

library(data.table)
library(e1071)

VCF_SUMMARY_V1.0_COLCLASSES = c("#CHROM"="character", "POS"="integer", "ID"="character", "REF"="character", "ALT"="character", "QUAL"="numeric", "FILTER"="character", 
                                "POS_NT"="integer", "REF_NT"="character", "ALT_NT"="character", "DP"="integer", "CAO"="integer", "NORM_CAO"="numeric", "CAF"="numeric",
                                "R1_PLUS_AO"="integer", "R1_MINUS_AO"="integer", "R2_PLUS_AO"="integer", "R2_MINUS_AO"="integer",
                                "R1_PLUS_MED_RP"="numeric", "R1_MINUS_MED_RP"="numeric", "R2_PLUS_MED_RP"="numeric", "R2_MINUS_MED_RP"="numeric",
                                "R1_PLUS_MED_BQ"="numeric", "R1_MINUS_MED_BQ"="numeric", "R2_PLUS_MED_BQ"="numeric", "R2_MINUS_MED_BQ"="numeric",
                                "R1_PLUS_MED_NM"="numeric", "R1_MINUS_MED_NM"="numeric", "R2_PLUS_MED_NM"="numeric", "R2_MINUS_MED_NM"="numeric",
                                "LOCATION"="character", "REF_CODON"="character", "ALT_CODON"="character", "REF_AA"="character", "ALT_AA"="character", 
                                "AA_CHANGE"="character", "AA_POS"="character", "MATCHES_MUT_SIG"="character")

AA_CODONS_LIST<- list("A"=c("GCC", "GCT", "GCA", "GCG"), "C"=c("TGC", "TGT"), "D"=c("GAC", "GAT"), "E"=c("GAG", "GAA"), "F"=c("TTC", "TTT"), 
                 "G"=c("GGC", "GGG", "GGA", "GGT"), "H"=c("CAC", "CAT"), "I"=c("ATC", "ATT", "ATA"), "K"=c("AAG", "AAA"), 
                 "L"=c("CTG", "CTC", "TTG", "CTT", "CTA", "TTA"), "M"=c("ATG"), "N"=c("AAC", "AAT"), 
                 "P"=c("CCC", "CCT", "CCA", "CCG"), "Q"=c("CAG", "CAA"), "R"=c("CGC", "AGG", "CGG", "AGA", "CGA", "CGT"), 
                 "S"=c("AGC", "TCC", "TCT", "AGT", "TCA", "TCG"), "T"=c("ACC", "ACA", "ACT", "ACG"), "V"=c("GTG", "GTC", "GTT", "GTA"), 
                 "W"=c("TGG"), "Y"=c("TAC", "TAT"), "*"=c("TGA", "TAG", "TAA"))

STOP_CODONS<- c("TGA", "TAG", "TAA")

aa_codon_counts<- sapply(AA_CODONS_LIST, length)

aa_codon_proportions<- aa_codon_counts/sum(aa_codon_counts)

positive_charged_aas<- c("R", "H", "K")
negative_charged_aas<- c("D", "E")
polar_uncharged_aas<- c("S", "T", "N", "Q", "C")
nonpolar_uncharged_aas<- c("A", "V", "I", "L", "M", "F", "Y", "W", "G", "P")
other_aas<- c("C", "G", "P")

aa_map<- list("A"="Ala", "C"="Cys", "D"="Asp", "E"="Glu", "F"="Phe", 
              "G"="Gly", "H"="His", "I"="Ile", "K"="Lys", "L"="Leu", 
              "M"="Met", "N"="Asn", "P"="Pro", "Q"="Gln", "R"="Arg", 
              "S"="Ser", "T"="Thr", "V"="Val", "W"="Trp", "Y"="Tyr",
              "*"="Ter")

get_aa_change_type<- function(x){
  
  if(x%in%positive_charged_aas){
    return("Positive")
  } else if(x%in%negative_charged_aas){
    return("Negative")
  } else if(x%in%polar_uncharged_aas){
    return("Polar")
  }else if(x%in%nonpolar_uncharged_aas){
    return("Nonpolar")
  } else{
    return("Other")
  }
}

aa_class_list<- list("Positive_charged"=positive_charged_aas, "Negative_charged"=negative_charged_aas, 
                     "Polar_uncharged"=polar_uncharged_aas, "Nonpolar_uncharged"=nonpolar_uncharged_aas, 
                     "Other"=other_aas, "Stop"=c("*"))

positive_charged_codons<- c("CGC", "AGG", "CGG", "AGA", "CGA", "CGT",   "CAC", "CAT",   "AAG", "AAA")
negative_charged_codons<- c("GAC", "GAT",   "GAG", "GAA")
polar_uncharged_codons<- c("AGC", "TCC", "TCT", "AGT", "TCA", "TCG",   "ACC", "ACA", "ACT", "ACG",   "AAC", "AAT",   "CAG", "CAA")
nonpolar_uncharged_codons<- c("GCC", "GCT", "GCA", "GCG",   "GTG", "GTC", "GTT", "GTA",   "ATC", "ATT", "ATA",   
                              "CTG", "CTC", "TTG", "CTT", "CTA", "TTA",   "ATG",   "TTC", "TTT",   "TAC", "TAT",   "TGG")

binding_motifs<- c("Puf3"="TGTAAATA", "Whi3"="TGCAT", "polyU"="TTTTTTA", "OSPHOS"="ATATTC")

#' Reads in variant calls in vcf.summary.txt format
#'
#' @param indir character path of input directory
#' @return data.table of all samples in the input dir
read_vcf_summary_files<- function(indir=".", colclasses=VCF_SUMMARY_V1.0_COLCLASSES){
  
  vcf_summary_file_pattern<- "var.cand.vcf.summary.txt"
  vcf_summary_files<- dir(path=indir, pattern=vcf_summary_file_pattern, full.names=TRUE)
  
  if(length(vcf_summary_files)==0){
    stop(paste("No var.cand.vcf.summary.txt files found in directory", vcf_summary_file_pattern))
  }
         
  vcf_summary_files_split<- sapply(strsplit(as.character(vcf_summary_files), "/", fixed=TRUE), tail, 1)
  sample_vector<- sapply(strsplit(as.character(vcf_summary_files_split), ".", fixed=TRUE), head, 1)
  
  vcf_summary_file_list<- lapply(vcf_summary_files, fread, sep="\t", header=TRUE, colClasses=colclasses)
  vcf_summary_file_list_nrows<- sapply(vcf_summary_file_list, nrow)
  
  # Run with fill=TRUE just in case any files differ in the number of columns
  vcf_summary_file_list_all<- rbindlist(vcf_summary_file_list, fill=TRUE)
  vcf_summary_file_list_all[,Sample:=factor(rep(sample_vector, vcf_summary_file_list_nrows), levels=sample_vector)]
  return(vcf_summary_file_list_all)
}


#' Gets a data.table matching coordinate positions to CBS PCR tile
#'
#' @param design_version character one of v0.1 or v0.2, specifying CBS primer tile design version
#' @return data.table with POS and TILE columns
get_tile_position_dt<- function(design_version="v0.1"){

  # Manually-curated 1-based start and stop positions for each tile across CBS
  # tile-seq designs
  tile_positions<- list(TILE_1=seq(244,368), TILE_2=seq(369,470), TILE_3=seq(471,584), TILE_4=seq(585,698), TILE_5=seq(699,812), 
                        TILE_6=seq(813,926), TILE_7=seq(927,1034), TILE_8=seq(1035,1148), TILE_9=seq(1149,1262), TILE_10=seq(1263,1376), 
                        TILE_11=seq(1377,1490), TILE_12=seq(1491,1604), TILE_13=seq(1605,1715), TILE_14=seq(1716,1823), TILE_15=seq(1824,1971))
  
  # ArcherDX AMP designs
  if(design_version=="v0.2"){
    tile_positions<- list(TILE_1=seq(244,368), TILE_2=seq(369,467), TILE_3=seq(468,584), TILE_4=seq(585,698), TILE_5=seq(699,815), 
                          TILE_6=seq(806,921), TILE_7=seq(922,1029), TILE_8=seq(1030,1148), TILE_9=seq(1149,1263), TILE_10=seq(1264,1382), 
                          TILE_11=seq(1383,1485), TILE_12=seq(1486,1596), TILE_13=seq(1597,1715), TILE_14=seq(1716,1823), TILE_15=seq(1824,1971))
  }
  
  tile_labels<- names(tile_positions)
  
  tile_positions_lengths<- sapply(tile_positions, length)
  
  tile_positions_dt<- data.table(POS=unlist(tile_positions), TILE=as.factor(rep(tile_labels, tile_positions_lengths)))
  
  return(tile_positions_dt)
}


#' Gets the type of variant given a VCF REF and ALT field
#'
#' @param ref character REF
#' @param alt character ALT
#' @return character one of {"SNP", "di_nt_MNP", "tri_nt_MNP", "MNP", "[123456]_nt_HAPLO", "INS", "DEL"}
get_var_type<- function(ref, alt, split_mnps=TRUE){
  
  len_ref<- nchar(ref)
  len_alt<- nchar(alt)
  ref_c<- unlist(strsplit(ref, ""))
  alt_c<- unlist(strsplit(alt, ""))
  
  if(len_ref == len_alt){
    if(len_ref == 1){
      return("SNP")
      }
    else if(split_mnps) {
      if(len_ref == 2){
        return("di_nt_MNP")
      }
      hd<- hamming.distance(sub(",", "", ref_c, fixed=T), sub(",", "", alt_c, fixed=T))
      if(len_ref == 3){
        if(hd == 2){
          if(grepl(",", ref, fixed=T)){
            return("2_nt_HAPLO")
          } else {
            return("di_nt_MNP")
          }
        } else {
          return("tri_nt_MNP")
        }
      } else {
        if(hd == 2){
          return("2_nt_HAPLO")
        } else if (hd == 3){
          return("3_nt_HAPLO")
        } else if (hd == 4){
          return("4_nt_HAPLO")
        } else if (hd == 5){
          return("5_nt_HAPLO")
        } else if (hd == 6){
          return("6_nt_HAPLO")
        }
      }
    } else{
    return("MNP")
    }
  } else if(len_ref < len_alt){
    return("INS")
  } else if(len_ref > len_alt){
    return("DEL")
  }
}


#' Annotates data.table of vcf.summary.txt formatted data
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param mapping_dt data.table mapping sample name to desired fraction label
#' @param tile_positions data.table with POS and TILE columns, for annotating PCR tiles
#'   NULL if no tile annotation desired.
#' @return data.table of all samples in the input directory.
annotate_calls<- function(in_dt, mapping_dt=NULL, tile_positions_dt=NULL){
  
  copy_dt<- copy(in_dt)
  
  copy_dt[,VAR_ID:=as.factor(paste(`#CHROM`,POS,REF,ALT,sep=":"))]
  
  if(!is.null(tile_positions_dt)){
    tile_positions_match<- match(copy_dt$POS, tile_positions_dt$POS)
    copy_dt[,TILE:=as.factor(tile_positions_dt[tile_positions_match,TILE])]
  }
  
  copy_dt[,TYPE:=get_var_type(REF, ALT), by=seq_len(nrow(copy_dt))]
  copy_dt[,SUBST:=as.factor(paste(REF_NT, ALT_NT, sep=":"))]

  copy_dt[,TYPE:=as.factor(TYPE)]
  copy_dt[,REF_NT:=as.factor(REF_NT)]
  copy_dt[,ALT_NT:=as.factor(ALT_NT)]
  copy_dt[,`#CHROM`:=as.factor(`#CHROM`)]
  copy_dt[,FILTER:=as.factor(FILTER)]
  copy_dt[,UP_REF_NT:=as.factor(UP_REF_NT)]
  copy_dt[,DOWN_REF_NT:=as.factor(DOWN_REF_NT)]
  copy_dt[,AA_POS2:=as.numeric(sapply(
    as.character(AA_POS), summarize_str_list)),
          by=seq_len(nrow(copy_dt))]
  
  copy_dt[, VAR_TYPE:=ifelse(REF_AA==ALT_AA, "Silent", "Missense"), 
          by=seq_len(nrow(copy_dt))]
  
  copy_dt[ALT_AA=="*", VAR_TYPE:="Nonsense"]
  copy_dt[,VAR_TYPE:=factor(VAR_TYPE, levels=c("Silent", "Missense", "Nonsense"))]
  
  if(!is.null(mapping_dt)){
    copy_dt<- add_fraction_ids(copy_dt, mapping_dt)
  }
  
  copy_dt[,log10_CAF:=log10(CAF)]
  
  return(copy_dt)
}


#' Summarizes counts of unique variants and AA changes for each sample
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @return data.table of counts for variants and AA changes, by each variant type
summarize_counts<- function(in_dt){
  
  calls_by_sample<- in_dt[,length(unique(VAR_ID)),by=.(Sample)]
  calls_by_sample$SNPs<- in_dt[nchar(REF)==1,length(unique(VAR_ID)),by=.(Sample)]$V1
  calls_by_sample$MNPs<- in_dt[nchar(REF)>1,length(unique(VAR_ID)),by=.(Sample)]$V1
  
  # This is not necessarily accurate for di-nts and comparison to theoretical increase of variants from SNP to (SNP + di-nt MNP)
  calls_by_sample$di_nt_MNPs<- in_dt[TYPE=="di_nt_MNP", length(unique(VAR_ID)),by=.(Sample)]$V1
  
  # by virtue of the above point, this could have di-nt MNPs in it as well
  calls_by_sample$tri_nt_MNPs<- in_dt[TYPE=="tri_nt_MNP", length(unique(VAR_ID)),by=.(Sample)]$V1
  
  # Multi-AA changes are separated and each AA change called unique
  # At some point we may actually want to consider them different
  calls_by_sample$AA_changes<- in_dt[,length(unique(unlist(strsplit(AA_CHANGE, ",")))),by=.(Sample)]$V1
  calls_by_sample$AA_changes_SNPs<- in_dt[nchar(REF)==1, length(unique(unlist(strsplit(AA_CHANGE, ",")))),by=.(Sample)]$V1
  calls_by_sample$AA_changes_MNPs<- in_dt[nchar(REF)>1, length(unique(unlist(strsplit(AA_CHANGE, ",")))),by=.(Sample)]$V1
  
  # If the variants are off, so are the AA changes
  calls_by_sample$AA_changes_di_nt_MNPs<- in_dt[TYPE=="di_nt_MNP", length(unique(unlist(strsplit(AA_CHANGE, ",")))),by=.(Sample)]$V1
  calls_by_sample$AA_changes_tri_nt_MNPs<- in_dt[TYPE=="tri_nt_MNP", length(unique(unlist(strsplit(AA_CHANGE, ",")))),by=.(Sample)]$V1
  
  names(calls_by_sample)<- c("Sample", "Variant_calls", "Variant_calls_SNPs", "Variant_calls_MNPs", "Variant_calls_di_nt_MNPs", "Variant_calls_tri_nt_MNPs",
                             "AA_changes", "AA_changes_SNPs", "AA_changes_MNPs", "AA_changes_di_nt_MNPs", "AA_changes_tri_nt_MNPs")
  
  return(calls_by_sample)
}


#' Melts the summarized counts generated from summarize_counts()
#'
#' @param calls_by_sample data.table of variant and AA change calls for each sample
#' @param character id_vars variables to keep as IDs
#' @return data.table of melted counts
melt_summarized_counts<- function(calls_by_sample, id_vars=c("Sample")){
  calls_by_sample_melt<- melt(calls_by_sample, id.vars=id_vars, variable.name="Statistic", value.name="Count")
  nrows<- nrow(calls_by_sample_melt)
  calls_by_sample_melt[,Metric:=as.factor(rep(c("Variant_calls", "AA_changes"), each=nrows/2))]
  return(calls_by_sample_melt)
}


#' Generates a basic clustered heatmap
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param var1 character of x axis variable
#' @param var2 character of y axis variable
#' @param fill_var character of a numeric variable to use for fill color
#' @param na_val numeric or integer value to use for NA values
#' @param transform_fun character name of a transformation function for the fill_var
plot_heatmap<- function(in_dt, var1="AA_CHANGE", var2="Sample", fill_var="NORM_CAO", na_val=0.1, 
                        transform_fun="log2", agg_fun="median", scale_spec="row"){
  
  library(gplots)
  library(RColorBrewer)
  
  cast_formula<- as.formula(paste0(var1, " ~ ", var2))
  
  # First create a matrix of the data to be plotted
  heatmap_in<- dcast(in_dt, cast_formula, value.var=fill_var, fun.aggregate=get(agg_fun))
  
  heatmap_in_rownames<- heatmap_in[,var1,with=FALSE][[1]]
  heatmap_in<- heatmap_in[,-..var1]
  heatmap_in<- as.matrix(heatmap_in, rownames.value=heatmap_in_rownames)
  
  heatmap_in_nas<- is.na(heatmap_in)
  heatmap_in[heatmap_in_nas]<- na_val

  heatmap_in_final<- t(get(transform_fun)(heatmap_in))
  
  my_palette<- colorRampPalette(brewer.pal(9, "PuRd"))(n=100)
  
  heatmap.2(heatmap_in_final, trace="none", scale=scale_spec, col=my_palette, 
            symkey=FALSE, keysize=1, cexRow=1, srtRow=0,
            key.title=paste0(transform_fun, "(", fill_var, ")"), xlab=var1, ylab=var2)
  
  return(heatmap_in_final)
}


# Lack of normalization of features that depend on DP cause lack of generalization to other datasets

#' Centers with the robust median
#'
#' @param x numeric or integer vector
#' @param standardize logical indicating the data should also be standardized after centering.
#' @return numeric vector centered and possibly standardized
robust_center<- function(x, standardize=FALSE){
  centered_x<- x - median(x, na.rm=TRUE)
  if(standardize==TRUE){
    centered_x<- centered_x / sd(centered_x, na.rm=TRUE)
  }
  return(centered_x)
}


#' Scales numeric and integer columns of a data.table
#'
#' @param in_dt input data.table, can contain both numeric and non-numeric columns
#' @param standardize logical indicating the data should be standardized after centering.
#' @param nonscale_features character of integer or numeric features to not scale.
#'
#' @return data.table with numeric and integer columns centered and possibly standardized
scale_numeric_features<- function(in_dt, standardize=FALSE, nonscale_features=c("POS", "POS_NT", "AA_POS")){
  
  dt_copy<- copy(in_dt)
  
  # Add a sample name if the dataset does not have one already
  if(!"Sample"%in%names(dt_copy)){
    dt_copy[,Sample:="Mock_sample"]
  }
  
  nonscale_dt<- dt_copy[,..nonscale_features]
  remain_dt<- dt_copy[,-..nonscale_features]
  
  numeric_col_classes<- sapply(remain_dt, class)
  which_numeric<- numeric_col_classes%in%c("integer", "numeric", "single", "double")
  
  numeric_cols_dt<- remain_dt[,which_numeric,with=FALSE]
  nonnumeric_cols_dt<- remain_dt[,!which_numeric,with=FALSE]
  numeric_cols_dt[,Sample:=nonnumeric_cols_dt[,Sample]]
  
  numeric_features<- names(numeric_cols_dt)
  numeric_features<- numeric_features[!numeric_features%in%c("Sample")]
  
  numeric_cols_coerced_dt<- numeric_cols_dt[
    ,lapply(.SD, as.numeric), 
    by=.(Sample), .SDcols=numeric_features]
  
  numeric_cols_scaled_dt<- numeric_cols_coerced_dt[
    ,lapply(.SD, robust_center, standardize), 
    by=.(Sample), .SDcols=numeric_features]
  
  numeric_cols_scaled_dt[,Sample:=NULL]
  recombined_dt<- cbind(nonnumeric_cols_dt, numeric_cols_scaled_dt, nonscale_dt)
  
  return(recombined_dt)
}


#' Shifts values in a vector to the max value
#'
#' @param x numeric or integer vector
#' @return values shifted by the max value in x
max_shift<- function(x){
  shifted_x<- x - max(x)
  return(shifted_x)
}


#' Shifts values in a vector to the value of the first element
#'
#' @param x numeric or integer vector
#' @return values shifted by the first value in x
first_shift<- function(x){
  shifted_x<- x - x[1]
  return(shifted_x)
}


#' Gets the range of a numeric or integer vector
#'
#' @param x numeric or integer vector
#' @return range of x
get_range<- function(x){
  sorted_x<- sort(x)
  max_dist<- abs(x[length(x)] - x[1])
  return(max_dist)
}


#' Gets the studentized range of a numeric or integer vector
#'
#' @param x numeric or integer vector
#' @return studentized range of x
get_studentized_range<- function(x){
  sorted_x<- sort(x)
  max_dist<- abs(x[length(x)] - x[1])
  sd_range<- max_dist / sd(x)
  return(sd_range)
}


#' Gets the normalized range of a numeric or integer vector
#'
#' @param x numeric or integer vector
#' @return normalized range of x
get_normed_range<- function(x){
  sorted_x<- sort(x)
  max_dist<- abs(x[length(x)] - x[1])
  norm_range<- max_dist / median(x)
  return(norm_range)
}


#' Gets the standard error
#'
#' @param x numeric or integer vector
#' @return standard error
se<- function(x){
  res<- sd(x)/sqrt(length(x))
  return(res)
}


#' Gets the confidence interval bounds
#'
#' @param vals numeric or integer vector
#' @param min_ci logical which CI bound to return
#' @param alpha numeric signifance level
#' @return numeric CI bound
ci<- function(vals, min_ci=TRUE, alpha=0.05){
  a<- qnorm(1-alpha/2)
  se_res<- se(vals)
  mean_vals<- mean(vals)
  
  if(min_ci){
    ci_res<- mean_vals-a*se_res
  } else{
    ci_res<- mean_vals+a*se_res
  }
  return(ci_res)
}


#' Gets the root mean squared error
#'
#' @param predicted numeric or integer vector predicted values
#' @param truth numeric or integer vector known values
#' @return numeric RMSE
rmse<- function(predicted, truth){
  res<- sqrt(mean((predicted-truth)^2))
  return(res)
}

#' Subtracts magnitude of a numeric vector based on crosstalk percentage estimate
#'
#' @param x numeric or integer vector
#' @param xtalk_prop numeric estimate of barcode crosstalk proportion 
#' @return values corrected to remove contribution of crosstalk
subtract_xtalk<- function(x, xtalk_prop){
  corrected_x<- x - (max(x) * xtalk_prop)
  return(corrected_x)
}


numeric_median<- function(x){
  res<- as.numeric(median(x))
  return(res)
}


#' Collapses per-bp records into per-variant records
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param key_features character vector of keys to merge on. (Include your other variables).
#' @param agg_fun function to use to aggregate for each level.
#' @return data.table with per-bp statistics collapsed/aggregated
#' @details needed to ensure aggregation of data is not influenced by variant type
collapse_mnps<- function(in_dt, key_features=c("Sample", "VAR_ID"), agg_fun=numeric_median){
  
  copy_dt<- copy(in_dt)
  setkeyv(copy_dt, key_features)
  
  # The following is just for reference
  per_bp_features<- c("POS_NT", "REF_NT", "ALT_NT", "UP_REF_NT", "DOWN_REF_NT")
  
  numeric_col_classes<- sapply(copy_dt, class)
  which_numeric<- numeric_col_classes%in%c("integer", "numeric", "single", "double")
  
  numeric_cols_dt<- copy_dt[,which_numeric,with=FALSE]
  nonnumeric_cols_dt<- copy_dt[,!which_numeric,with=FALSE]
  
  # Add back in the key columns
  for(i in 1:length(key_features)){
    numeric_cols_dt[,key_features[i]:=nonnumeric_cols_dt[,key_features[i],with=FALSE]]
  }
  #numeric_cols_dt[,Sample:=nonnumeric_cols_dt[,Sample]]
  #numeric_cols_dt[,VAR_ID:=nonnumeric_cols_dt[,VAR_ID]]
  
  numeric_features<- names(numeric_cols_dt)
  # numeric_features is evaluated lazily in .SDcols, so explicitly remove the keys
  numeric_features<- numeric_features[
    !numeric_features%in%key_features]
  
  nonnumeric_features<- names(nonnumeric_cols_dt)
  nonnumeric_features<- nonnumeric_features[
    !nonnumeric_features%in%c(key_features)]
  
  # Aggregate numeric features; most features have duplicated values, 
  # but BQs are per-bp features to be aggregated
  numeric_cols_agg_dt<- numeric_cols_dt[
    ,lapply(.SD, agg_fun), 
    by=key_features, 
    .SDcols=numeric_features]
  
  # Similarly, we must collapse the nonnumeric features
  nonnumeric_cols_collapse_dt<- nonnumeric_cols_dt[
    ,lapply(.SD, head, 1), 
    by=key_features, 
    .SDcols=nonnumeric_features]
  
  merged_dt<- merge(nonnumeric_cols_collapse_dt, 
                    numeric_cols_agg_dt, 
                    by=key_features)
  
  return(merged_dt)
}


#' Removes multi-AA change variants
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @return data.table without multi-AA change variants (e.g. p.K247R,p.L248L)
#' @details needed to coerce AA_POS to integer for plotting
remove_multi_aas<- function(in_dt){
  copy_dt<- copy(in_dt)
  filt_dt<- copy_dt[!grepl(",", AA_CHANGE),]
  filt_dt[,AA_POS:=as.integer(AA_POS)]
  return(filt_dt)
}

#' Gets a list of results for a data.table filtered on increasing thresholds of a filter variable
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param filter_var character of a numeric or integer variable to filter on
#' @param res_var character of a variable to report for each threshold on filter_var
#' @param nthresholds integer number of thresholds for variable
#' @param comparator character of a inequality comparator
#' @return list 
get_count_by_filter_thresh<- function(in_dt, filter_var, res_var, n_thresholds, comparator=">="){
  
  min_val<- min(dt[[filter_var]])
  max_val<- max(dt[[filter_var]])
  thresholds<- seq(min_val, max_val, length.out=n_thresholds)
  
  res_list<- list(mode="list", length=n_thresholds)
  for(i in 1:n_thresholds){
    filter_expr<- paste0(filter_var, comparator, thresholds[i])
    res_list[[i]]<- in_dt[eval(parse(text=filter_expr)), res_var, with=FALSE]
  }
  names(res_list)<- thresholds
  return(res_list)
}


#' Applies a simple AF subtraction approach for removal of error
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @return data.table with AF subtract of the negative applied to other samples
subtract_af<- function(in_dt){
  
  copy_dt<- copy(in_dt)
  neg_dt<- copy_dt[Experiment=="Negative_control", .(VAR_ID, CAF)]
  
  # Merge the two tables so we can easily subtract the negative frequencies via a vectorized operation
  merged_dt<- merge(copy_dt[Experiment!="Negative_control"], neg_dt, by="VAR_ID", all.x=TRUE)
  
  # Set baseline to 0 for variants unique to a polysomal fraction
  merged_dt[is.na(CAF.y), CAF.y:=0.0]

  # Finally subtract the frequencies and remove those variants with negative resultant frequencies
  merged_dt[,CAF:=CAF.x-CAF.y]
  filtered_dt<- merged_dt[CAF>0,]
  filtered_dt[,log10_CAF:=log10(CAF)]
  
  return(filtered_dt)
}


standardize_vector<- function(x){
  res<- (x-mean(x, na.rm=TRUE))/sd(x, na.rm=TRUE)
  return(res)
}


#' Reverse complements a sequence
#'
#' @param nt_seq nucleotide sequence, should contain only {A,T,C,G,N}, case insensitive
#' @return character reverse complemented sequence
revcomp<- function(nt_seq){
  
  if(grepl("[^ATCGUNatcgun]", nt_seq)){
    stop("Sequence has invalid characters")
  }
  
  seq_rev<- paste(rev(unlist(strsplit(nt_seq, ""))), collapse="")
  seq_rev_sub<- chartr("ATCGUNatcgun", "TAGCANtagcan", seq_rev)
  return(seq_rev_sub)
}


summarize_str_list<- function(str_list, split_sep=",", summarization_stat="median"){
  split_unlisted<- as.integer(unlist(strsplit(str_list, split_sep)))
  summarized<- get(summarization_stat)(split_unlisted)
  return(summarized)
}


summarize_str_list_codons<- function(str_list, split_sep=",", summarization_stat="median", trna_expr=NULL){
  
  split_unlisted<- unlist(strsplit(str_list, split_sep))
  
  if(!is.null(trna_expr)){
    trna_match<- match(split_unlisted, trna_expr[,Codon])
    split_unlisted<- trna_expr[trna_match, Sum_log2_count]
  }
  
  summarized<- median(split_unlisted, na.rm=TRUE)
  return(summarized)
}


#' lapply-friendly version of %in%
#'
#' @param e_set character vector containing values to search in
#' @param x character to search
#' @return logical whether or not the x was found in e_set
is_in<- function(e_set, x){
  return(x%in%e_set)
}


#' Determines AA decoded by a specific codon
#'
#' @param codon character 3-nt codon
#' @param aa_codons list named list containing codons for each amino acid
#' @return character amino acid for the codon
aa_from_codon<- function(codon, aa_codons=AA_CODONS_LIST){
  aa<- names(aa_codons)[sapply(aa_codons, is_in, codon)]
  return(aa)
}


#' Determines AA class of a specific AA
#'
#' @param aa single letter AA
#' @param aa_classes list named list containing amino acids for each class
#' @return character class of the amino acid
class_from_aa<- function(aa, aa_classes=aa_class_list){
  aa_class<- names(aa_classes)[sapply(aa_classes, is_in, aa)]
  return(aa_class)
}


#' Generates expression entries for wobble codons
#'
#' @param hydrotrnaseq_summarized_dt data.table containing summarized expression values for tRNAs
#' @return data.table original data.table with entries for wobble codons
expand_wobble_pairs<- function(hydrotrnaseq_summarized_dt){
  
  wobble_anticodons<- hydrotrnaseq_summarized_dt[substr(Anticodon, 1, 1)%in%c("G", "T"), unique(Anticodon)]
  
  # For each anticodon with a G or T at the 5' end, there can be one other codon that can pair with it
  n_wobble_anticodons<- length(wobble_anticodons)

  # Initialize the data.table
  wobble_codon_dt<- data.table(Isotype=vector(mode="character", length=n_wobble_anticodons),
                               Anticodon=vector(mode="character", length=n_wobble_anticodons),
                               Codon=vector(mode="character", length=n_wobble_anticodons), 
                               Sum_log2_count=vector(mode="numeric", length=n_wobble_anticodons))
  
  # Iterate over the anticodons that can form wobble pairing, and create entries for wobble codons
  for(i in 1:length(wobble_anticodons)){
    anticodon<- wobble_anticodons[i]
    wobble_bp<- substr(anticodon, 1, 1)
    
    # These wobble pairing rules are the original described by Crick, which are actually conservative
    if(wobble_bp=="G"){
      wobble_anticodon<- paste0("A", substr(anticodon, 2, 3))
    } else if(wobble_bp=="T"){
      wobble_anticodon<- paste0("C", substr(anticodon, 2, 3))
    }
    
    wobble_codon<- revcomp(wobble_anticodon)
    wobble_aa<- names(aa_codons)[sapply(aa_codons, is_in, wobble_codon)]
    
    # Use the tRNA expression values of the canonical anticodon for the wobble codon
    wobble_codon_dt[i,]<- data.table(Isotype=wobble_aa, Anticodon=anticodon, Codon=wobble_codon, 
                                     Sum_log2_count=hydrotrnaseq_summarized_dt[Anticodon==anticodon, Sum_log2_count])
  }
  
  complete_dt<- rbind(hydrotrnaseq_summarized_dt, wobble_codon_dt)
  setkey(complete_dt, Isotype, Anticodon, Codon)
  return(complete_dt)
}


#' Converts human to mouse gene name conventions
#'
#' @param x character vector of human gene names
#' @return character vector converted to lowercase except for first letter
human_to_mouse_genename<- function(x){
  x_split<- strsplit(x, "")[[1]]
  first_char<- toupper(x_split[1])
  all_other_chars<- sapply(x_split[2:nchar(x)], tolower)
  x_formatted<- paste0(c(first_char, all_other_chars), collapse="")
  return(x_formatted)
}


#' Computes the coefficient of variation
#'
#' @param x vector of numeric or integer values
#' @return numeric
get_cv<- function(x){
  mean_x<- mean(x, na.rm=TRUE)
  sd_x<- sd(x, na.rm=TRUE)
  cv_x<- sd_x/mean_x
  return(cv_x)
}


#' Annotates and collapses per-bp records into per-variant records
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param mapping_dt data.table mapping sample name to desired fraction label
#' @param tile_positions data.table with POS and TILE columns, for annotating PCR tiles. 
#' NULL if no tile annotation desired.
#' @param key_features character vector of keys to merge on. (Include your other variables).
#' @return data.table
postprocess_vcf_summary_dt<- function(in_dt, mapping_dt=NULL, tile_positions_dt=NULL, 
                                      key_features=c("Sample", "VAR_ID")){
  copy_dt<- copy(in_dt)
  annot_dt<- annotate_calls(copy_dt, mapping_dt, tile_positions_dt)
  collapse_dt<- collapse_mnps(in_dt=annot_dt, key_features=key_features)
  return(collapse_dt)
}


#' Computes coverage (DP) over positions
#'
#' @param in_dt data.table in vcf.summary.txt format
#' @param key_features character vector of keys to merge on. (Include your other variables).
#' @param integer stepsize: compute proportion between 0 and max coverage with this stepsize.
#' a smaller stepsize returns a more granular profile but takes longer time to compute.
#' @return data.table
waterfall_ecdf<- function(in_dt, key_features=c("Sample"), stepsize=10){
  
  max_cov<- in_dt[,max(V4)]
  
  # Modify max_cov slighlty so we can have an appropriate stepsize
  # to split data evenly
  while(max_cov%%stepsize == 0){
    max_cov<- max_cov + 1
  }
  
  # We compute the ECDF then plot values for 0 to max coverage
  ecdf_res_dt<- in_dt[,.(Proportion_greater_than=1-ecdf(V4)(seq(0,max_cov,stepsize)),
                         Coverage=seq(0,max_cov,stepsize)), by=key_features]
  return(ecdf_res_dt)
}


#' Re-computes CAF by averaging CAF over positions in MNPs
#'
#' @param in_dt data.table vcf.summary.txt per-bp calls prior to collapse
#' @return data.table with CAF updated for MNPs
recompute_caf<- function(in_dt){
  copy_dt<- copy(in_dt)
  recomp_dt<- copy_dt[,CAF:=max(CAO/DP), by=.(VAR_ID)]
  return(recomp_dt)
}


z_trans<- function(x){
  z<- (x -  mean(x)) / sd(x)
  return(z)
}


robust_z<- function(x){
  rz<- (x - median(x)) / mad(x)
  return(rz)
}


#' Coverts long to short AA formats
#'
#' @param aa_change character HGVS amino acid change, e.g. p.Ala41Thr
convert_aa_notation<- function(aa_change){
  
  aa_change_strip<- strsplit(as.character(aa_change), ".", fixed=T)
  
  if(length(aa_change_strip[[1]])==1){
    aa_change_strip<- aa_change
  } else{
    aa_change_strip<- sapply(aa_change_strip, "[", 2)
  }
  
  pos<- gsub(pattern="[[:alpha:]]|[[:punct:]]", replacement="", aa_change_strip)
  
  aa_change_no_int<- gsub(pattern="[[:digit:]]", replacement=":", aa_change_strip)
  
  aa_change_no_int_split<- unlist(strsplit(aa_change_no_int, ":+"))
  
  final_res<- c()
  for(e in 1:length(aa_change_no_int_split)){
    
    if(e==2){
      final_res<- append(final_res, pos)
      
      if(grepl("[[:punct:]]", aa_change_no_int_split[e])){
        match_res<- names(aa_map)[which(aa_change_no_int_split[1]==aa_map)]
        final_res<- append(final_res, match_res)
        next
      }
    }
    match_res<- names(aa_map)[which(aa_change_no_int_split[e]==aa_map)]
    final_res<- append(final_res, match_res)
  }
  
  final_res<- paste0(c("p.",final_res), collapse="")
  return(final_res)
}

