#!/usr/bin/env/python
"""Runs satmut_utils."""

import argparse
import logging
import os
import pysam
import sys
import tempfile

from analysis.read_preprocessor import FastqPreprocessor, UMIExtractor, ReadGrouper, \
    ConsensusDeduplicatorPreprocessor, ConsensusDeduplicator, ReadMasker, QnameVerification
import analysis.read_editor as ri
from analysis.references import get_ensembl_references, index_reference
from analysis.seq_utils import FASTA_INDEX_SUFFIX
from analysis.variant_caller import VariantCaller
import core_utils.file_utils as fu
from core_utils.string_utils import none_or_str
from definitions import AMP_UMI_REGEX, GRCH38_FASTA, QNAME_SORTS, INT_FORMAT_INDEX, DEFAULT_MUT_SIG, VALID_MUT_SIGS
from scripts.run_bowtie2_aligner import workflow as baw


__author__ = "Ian Hoskins"
__credits__ = ["Ian Hoskins"]
__license__ = "GPL"
__version__ = "1.0"
__maintainer__ = "Ian Hoskins"
__email__ = "ianjameshoskins@utexas.edu"
__status__ = "Development"

_logger = logging.getLogger(__name__)

# Consider putting the following in a logging config file
_logger.setLevel(logging.DEBUG)
_fhandler = logging.FileHandler("stderr.log")
_fhandler.setLevel(logging.DEBUG)
_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
_fhandler.setFormatter(_formatter)
_logger.addHandler(_fhandler)

DEFAULT_TEMPDIR = os.getenv("SCRATCH", "/tmp")
tempfile.tempdir = DEFAULT_TEMPDIR

SIM_WORKFLOW = "sim"
CALL_WORKFLOW = "call"


def parse_commandline_params(args):
    """Parses command line parameters.

    :param list args: command line arguments, no script name
    :return argparse.Namespace: namespace object with dict-like access
    """

    # Common satmut_utils options
    parser = argparse.ArgumentParser(description="%s arguments" % __file__)

    # Enforce that ensembl_id and reference are mutually exclusive and that at least one is provided
    group = parser.add_mutually_exclusive_group(required=True)

    group.add_argument("-i", "--ensembl_id", type=str,
                       help='Ensembl gene (ENSG) or transcript (ENST) ID to use to select a transcript reference. '
                            'Include minor version number, e.g. ENST00000398165.7')

    group.add_argument("-r", "--reference", type=str, help='Reference FASTA for alignment.')

    parser.add_argument("-x", "--reference_dir", type=str, default="./references",
                        help='Directory containing curated reference files.')

    parser.add_argument("-z", "--race_like", action="store_true",
                        help='Flag for data generated from a RACE-like chemistry with R1s starting at variable ends '
                             'and R2s starting at primers.')

    parser.add_argument("-p", "--primers", type=none_or_str,
                        help='Optional primer BED file with a strand field. Recommended for removing synthetic errors '
                             'from alignments.')

    parser.add_argument("-o", "--outdir", type=str, default=".",
                        help='Optional output directory. Default current working directory.')

    parser.add_argument("-j", "--nthreads", type=int, default=FastqPreprocessor.NCORES,
                        help='Number of threads to use for bowtie2 alignment and BAM sorting operations. '
                             'Default %i, autodetect.' % FastqPreprocessor.NCORES)

    # Subcommands
    subparsers = parser.add_subparsers(title='subcommands', help='sub-command help', dest="subcommand", required=True)

    # sim subcommand
    parser_sim = subparsers.add_parser(SIM_WORKFLOW, help='%s help' % SIM_WORKFLOW)
    parser_sim.set_defaults(func=sim_workflow)

    parser_sim.add_argument("-a", "--alignments", required=True, type=str,
                            help='BAM file containing alignments to edit.')

    parser_sim.add_argument("-v", "--vcf",  required=True, type=str,
                            help='VCF file specifying variants to edit. Should have an AF INFO field for each variant, '
                                 'specifying the fraction of fragments with overlapping coverage to edit into.')

    parser_sim.add_argument("-b", "--edit_buffer", type=int,
                            help='Buffer +/- the edit coordinate positions (s) to check for pre-existing errors in reads. '
                                 'Used to restrict phasing of true variants with errors, leading to false negatives.')

    parser_sim.add_argument("-f", "--force_edit", action="store_true",
                            help='Flag to force editing of variants despite invalid variant configurations (AF sum > 1).')

    parser_sim.add_argument("-s", "--random_seed", type=int, default=9, help='Seed for random read sampling.')

    # call subcommand
    parser_call = subparsers.add_parser(CALL_WORKFLOW, help='%s help' % CALL_WORKFLOW)
    parser_call.set_defaults(func=call_workflow)

    parser_call.add_argument("-1", "--fastq1", required=True, type=str, help='R1 FASTQ.')

    parser_call.add_argument("-2", "--fastq2", required=True, type=str, help='R2 FASTQ.')

    parser_call.add_argument("-5", "--r1_fiveprime_adapters", required=True, type=str,
                             help='Comma-delimited R1 5\' adapters.')

    parser_call.add_argument("-3", "--r1_threeprime_adapters", required=True, type=str,
                             help='Comma-delimited R1 3\' adapters.')

    parser_call.add_argument("-g", "--transcript_gff", type=str,
                             help='GFF file containing transcript metafeatures and exon features. The GFF must be from 5\' '
                                  'to 3\', regardless of strand, and contain transcript, exon, CDS, and stop_codon features.')

    parser_call.add_argument("-k", "--gff_reference", type=str, help='Reference FASTA for the GFF.')

    parser_call.add_argument("-t", "--targets", type=str,
                             help='Optional target BED file. Only variants intersecting the targets will be reported. '
                                  'Contig names in the target file should match the contig name of the reference FASTA. '
                                  'Provided -i, the name should match a single contig in '
                                  'appris_human_v1_actual_regions_contigs.txt.')

    parser_call.add_argument("-d", "--consensus_deduplicate", action="store_true",
                             help='For UMIs at the start of R1, flag to deduplicate and generate consensus reads.')

    parser_call.add_argument("-u", "--umi_regex", type=str, default=AMP_UMI_REGEX,
                             help='UMI regular expression to be passed to umi_tools extract command.')

    parser_call.add_argument("-s", "--mutagenesis_signature", type=str, default=DEFAULT_MUT_SIG,
                             help='Mutagenesis signature. One of NNN, NNK, or NNS.')

    parser_call.add_argument("-q", "--min_bq", type=int, default=VariantCaller.VARIANT_CALL_MIN_BQ,
                             help='Min base quality to consider a position for variant calling. Default %i.' %
                                  VariantCaller.VARIANT_CALL_MIN_BQ)

    parser_call.add_argument("-e", "--max_nm", type=int, default=VariantCaller.VARIANT_CALL_MAX_NM,
                             help='Max edit distance to consider a read pair for variant calling. Default %i.' %
                                  VariantCaller.VARIANT_CALL_MAX_NM)

    parser_call.add_argument("-m", "--min_supporting", type=int, default=VariantCaller.VARIANT_CALL_MIN_DP,
                             help='Min mate-concordant counts for variant calling. Default %i.' %
                                  VariantCaller.VARIANT_CALL_MIN_DP)

    parser_call.add_argument("-w", "--max_mnp_window", type=int, default=VariantCaller.VARIANT_CALL_MAX_MNP_WINDOW,
                             help='Max window to search for a MNP and merge phased SNPs. Must be between 1 and 3.'
                                  'Any consecutive SNPs within this window will be merged into a MNP, to the exclusion '
                                  'of its component SNPs. Default %i.' % VariantCaller.VARIANT_CALL_MAX_MNP_WINDOW)

    parser_call.add_argument("-n", "--ntrimmed", type=int, default=FastqPreprocessor.NTRIMMED,
                             help='Max number of adapters to trim from each read. Useful for trimming amplicons with '
                                  'vector-transgene alignment. Default %i.' % FastqPreprocessor.NTRIMMED)

    parser_call.add_argument("-l", "--overlap_length", type=int, default=FastqPreprocessor.OVERLAP_LEN,
                             help='Number of read bases overlapping the adapter sequence(s) to consider for trimming. '
                                  'Default %i.' % FastqPreprocessor.OVERLAP_LEN)

    parser_call.add_argument("-b", "--trim_bq", type=int, default=FastqPreprocessor.TRIM_QUALITY,
                             help='Base quality for 3\' trimming. Default %i.' % FastqPreprocessor.TRIM_QUALITY)

    parser_call.add_argument("-v", "--omit_trim", action="store_true",
                             help='Flag to turn off adapter and 3\' base quality trimming. Useful for simulated data '
                                  'that has already been adapter-trimmed.')

    parser_call.add_argument("-c", "--contig_del_threshold", type=int, default=ConsensusDeduplicator.CONTIG_DEL_THRESH,
                             help='If -z (RACE-like chemistry) and -cd (consensus deduplicate) are provided, '
                                  'convert deletions to N that are larger than this threshold. Required as some R2s '
                                  'may share the same R1 [UMI x position] but align to different coordinates. To '
                                  'generate consensus R2 contigs, merging R2s may leave large gaps that will be '
                                  'reassigned the unknown base N if the gap is greater than this threshold. This allows'
                                  'reasonable reporting of fragment coverage. To avoid this behavior, provide -f.')

    parser_call.add_argument("-f", "--primer_fasta", type=none_or_str,
                             help='If -cd, this may optionally be set to append originating R2 primer sequences to read names.'
                                  'Useful for RACE-like (e.g. AMP) libraries to prohibit R2 merging. That is, without '
                                  'this flag, tiled R2s sharing the same R1 will be merged into contigs during '
                                  'consensus deduplication (-cd).')

    parser_call.add_argument("-a", "--primer_nm_allowance", type=int, default=UMIExtractor.PRIMER_NM_ALLOW,
                             help='If -f, find primers in R2 with up to this many edit operations.')


    parsed_args = parser.parse_args(args)
    return parsed_args


def get_sim_reference(reference_dir, ensembl_id, ref, outdir=ri.ReadEditor.DEFAULT_REFERENCE_DIR):
    """Get and build index files for the sim workflow reference FASTA.

    :param str reference_dir: directory containing curated APPRIS reference files
    :param str ensembl_id: Ensembl gene or transcript ID, with version number
    :param str ref: path to reference FASTA used in alignment. Must be bowtie2 FM-index and samtools faidx indexed.
    :param str outdir: optional output dir for the reference files
    :return str: reference FASTA filepath
    """

    if not os.path.exists(outdir):
        os.mkdir(outdir)

    # Determine if the provided Ensembl ID is found in the curated APPRIS references
    if ensembl_id is not None:
        if ref is not None:
            raise RuntimeError("Both an Ensembl ID and a reference FASTA were provided. Please choose one.")

        ref_fa, _ = get_ensembl_references(reference_dir=reference_dir, ensembl_id=ensembl_id, outdir=outdir)
    else:
        ref_fa = ref
        index_reference(ref_fa)

    return ref_fa


def get_call_references(reference_dir, ensembl_id, ref, transcript_gff, gff_reference,
                        outdir=VariantCaller.VARIANT_CALL_REFERENCE_DIR):
    """Get and/or build index files for references.

    :param str reference_dir: directory containing curated APPRIS reference files
    :param str | None ensembl_id: Ensembl gene or transcript ID, with version number
    :param str | None ref: path to reference FASTA used in alignment. Must be bowtie2 FM-index and samtools faidx indexed.
    :param str transcript_gff: GFF/GTF file containing transcript metafeatures and exon features, in 5' to 3' order, \
    regardless of strand. Ordering is essential.
    :param str gff_reference: reference FASTA corresponding to the GFF features
    :param str outdir: optional output dir for the reference files
    :return tuple: (ref_fa, gff, gff_ref) filepaths
    """

    if not os.path.exists(outdir):
        os.mkdir(outdir)

    gff = transcript_gff
    gff_ref = gff_reference

    # Determine if the provided Ensembl ID is found in the curated APPRIS references
    if ensembl_id is not None:
        ref_fa, gff = get_ensembl_references(reference_dir=reference_dir, ensembl_id=ensembl_id, outdir=outdir)
        gff_ref = os.path.join(reference_dir, GRCH38_FASTA)
    else:
        ref_fa = ref
        index_reference(ref_fa)

        # Make sure the GFF reference has a samtools index file
        if not os.path.exists(fu.add_extension(ref, FASTA_INDEX_SUFFIX)):
            _logger.info("Indexing FASTA %s." % ref)
            pysam.faidx(ref)

    return ref_fa, gff, gff_ref


def sim_workflow(bam, vcf, race_like,
                 ensembl_id=ri.ReadEditor.DEFAULT_ENSEMBL_ID, reference_dir=ri.ReadEditor.DEFAULT_REFERENCE_DIR,
                 ref=ri.ReadEditor.DEFAULT_REF, primers=ri.ReadEditor.DEFAULT_PRIMERS,
                 outdir=ri.ReadEditor.DEFAULT_OUTDIR, random_seed=ri.ReadEditor.DEFAULT_SEED,
                 force_edit=ri.ReadEditor.DEFAULT_FORCE, nthreads=ri.ReadEditor.DEFAULT_NTHREADS):
    """Runs the satmut_utils sim workflow.

    :param str bam: BAM file to edit into
    :param str vcf: VCF file specifying variants to edit
    :param bool race_like: is the data produced by RACE-like (e.g. AMP) data? Default False.
    :param str | None ensembl_id: Ensembl gene or transcript ID, with version number
    :param str reference_dir: directory containing curated APPRIS reference files. Default ./references.
    :param str ref: indexed reference FASTA
    :param str | None primers: feature file of primer locations for read masking and primer detection
    :param str outdir: Optional output directory to store generated FASTQs and BAM
    :param int random_seed: seed for random qname sampling
    :param bool force_edit: flag to attempt editing of variants despite a NonconfiguredVariant exception.
    :param int nthreads: Number of threads to use for SAM/BAM operations and alignment. Default 0 (autodetect) \
    for samtools operations. If 0, will pass 1 to bowtie2 --threads.
    :return tuple: (str | None, str, str | None) paths of the edited BAM, R1 FASTQ, R2 FASTQ
    """

    # Unfortunately sort-order harmony with samtools sort -n requires we know the format of the qname
    # Check to make sure we have either Illumina format or single integer read names
    if primers is not None:
        _ = QnameVerification(bam=bam)

    if not os.path.exists(outdir):
        os.mkdir(outdir)

    ref_fa = get_sim_reference(
        reference_dir=reference_dir, ensembl_id=ensembl_id, ref=ref, outdir=os.path.join(outdir, "references"))

    out_prefix = fu.remove_extension(os.path.basename(bam))

    # Run the editing workflow
    output_bam, zipped_r1_fastq, zipped_r2_fastq = ri.ReadEditor(
        bam=bam, variants=vcf, ref=ref_fa, race_like=race_like, primers=primers,
        output_dir=outdir, output_prefix=out_prefix, random_seed=random_seed,
        force_edit=force_edit, nthreads=nthreads).workflow()

    return output_bam, zipped_r1_fastq, zipped_r2_fastq


def call_workflow(fastq1, fastq2, r1_fiveprime_adapters, r1_threeprime_adapters, race_like,
                  ensembl_id=VariantCaller.VARIANT_CALL_ENSEMBL_ID,
                  reference_dir=VariantCaller.VARIANT_CALL_REFERENCE_DIR,
                  ref=VariantCaller.VARIANT_CALL_REF, transcript_gff=VariantCaller.VARIANT_CALL_GFF,
                  gff_reference=VariantCaller.VARIANT_CALL_GFF_REF, targets=VariantCaller.VARIANT_CALL_TARGET,
                  outdir=VariantCaller.VARIANT_CALL_OUTDIR, primers=VariantCaller.VARIANT_CALL_PRIMERS,
                  primer_fa=UMIExtractor.PRIMER_FASTA, primer_nm_allowance=UMIExtractor.PRIMER_NM_ALLOW,
                  consensus_dedup=VariantCaller.VARIANT_CALL_CDEDUP, umi_regex=AMP_UMI_REGEX,
                  contig_del_thresh=ConsensusDeduplicator.CONTIG_DEL_THRESH,
                  min_bq=VariantCaller.VARIANT_CALL_MIN_BQ, max_nm=VariantCaller.VARIANT_CALL_MAX_NM,
                  min_supporting_qnames=VariantCaller.VARIANT_CALL_MIN_DP,
                  max_mnp_window=VariantCaller.VARIANT_CALL_MAX_MNP_WINDOW,
                  nthreads=FastqPreprocessor.NCORES, ntrimmed=FastqPreprocessor.NTRIMMED,
                  overlap_len=FastqPreprocessor.OVERLAP_LEN, trim_bq=FastqPreprocessor.TRIM_QUALITY,
                  omit_trim=FastqPreprocessor.TRIM_FLAG, mut_sig=DEFAULT_MUT_SIG):
    r"""Runs the satmut_utils call workflow.

    :param str fastq1: path of the R1 FASTQ
    :param str fastq2: path of the R2 FASTQ
    :param str r1_fiveprime_adapters: comma-delimited 5' adapters to trim from R1
    :param str r1_threeprime_adapters: comma-delimited 3' adapters to trim from R1
    :param bool race_like: is the data produced by RACE-like (e.g. AMP) data? Default False.
    :param str | None ensembl_id: Ensembl gene or transcript ID, with version number
    :param str reference_dir: directory containing curated APPRIS reference files. Default ./references.
    :param str | None ref: path to reference FASTA used in alignment. Must be bowtie2 FM-index and samtools faidx indexed.
    :param str | None transcript_gff: GFF/GTF file containing transcript metafeatures and exon features, in 5' to 3' \
    order, regardless of strand. Ordering is essential.
    :param str | None gff_reference: reference FASTA corresponding to the GFF features
    :param str | None targets: BED or GFF containing target regions to call variants in
    :param str outdir: optional output dir for the results
    :param str | None primers: BED or GFF file containing primers to mask. Must contain a strand field.
    :param str | None primer_fa: primer FASTA. Useful for annotating reads with originating tile. Default None.
    :param int primer_nm_allowance: Max edit distance a R2 can have to match a primer. Default 3.
    :param bool consensus_dedup: should consensus bases be generated during deduplication? Default False.
    :param str umi_regex: regex for matching the UMIs (see umi_tools for docs)
    :param int contig_del_thresh: max deletion length for which del/N gaps in the merged R2 contig are called
    :param int min_bq: min base qual; should be >= 1 such that masked primers do not contribute to depth
    :param int max_nm: max edit distance to consider a read for variant calling
    :param int min_supporting_qnames: min number of fragments with R1-R2 concordant coverage for which to keep a variant
    :param int max_mnp_window: max number of consecutive nucleotides to search for MNPs
    :param int nthreads: Number of threads to use for BAM operations. Default 0 (autodetect).
    :param int ntrimmed: Max number of adapters to trim from each read. Default 4.
    :param int overlap_len: number of bases to match in read to trim. Default 8.
    :param int trim_bq: quality score for cutadapt quality trimming at the 3' end. Default 15.
    :param bool omit_trim: flag to turn off adapter and 3' base quality trimming. Default False.
    :param str mut_sig: mutagenesis signature- one of {NNN, NNK, NNS}. Default NNK.
    :return tuple: (VCF, BED) filepaths
    :raises NotImplementedError: if mut_sig is not one of NNN, NNK, NNS; or if not 1 <= max_mnp_window <= 3
    """

    if mut_sig not in VALID_MUT_SIGS:
        raise NotImplementedError("Mutation signature %s not one of NNN, NNK, or NNS" % mut_sig)

    if max_mnp_window not in {1, 2, 3}:
        raise NotImplementedError("Mutation signature %s not one of NNN, NNK, or NNS" % mut_sig)

    # Unfortunately sort-order harmony with samtools sort -n requires we know the format of the qname
    # Check to make sure we have either Illumina format or single integer read names
    if primers is not None:
        qv = QnameVerification(fastq=fastq1)
        sort_cmd = QNAME_SORTS[qv.format_index]

    # Get and index the references
    ref_fa, gff, gff_ref = get_call_references(
        reference_dir=reference_dir, ensembl_id=ensembl_id, ref=ref, transcript_gff=transcript_gff,
        gff_reference=gff_reference, outdir=os.path.join(outdir, "references"))

    fqp_r1 = fastq1
    fqp_r2 = fastq2
    if consensus_dedup:
        # Run the first part of umi_tools based deduplication: UMI extraction. Note this should take place
        # before we have trimmed adapters as for umi_tools the adapter is used for "anchoring" the UMI.
        ue = UMIExtractor(r1_fastq=fastq1, r2_fastq=fastq2, umi_regex=umi_regex,
                          primer_fasta=primer_fa, primer_nm_allow=primer_nm_allowance, outdir=outdir)
        fqp_r1 = ue.r1_out_fastq
        fqp_r2 = ue.r2_out_fastq

    # Run the FASTQ preprocessing workflow which includes adapter trimming and 3' BQ trimming
    fqp = FastqPreprocessor(
        f1=fqp_r1, f2=fqp_r2, r1_fiveprime_adapters=r1_fiveprime_adapters, r1_threeprime_adapters=r1_threeprime_adapters,
        outdir=outdir, ncores=nthreads, trim_bq=trim_bq, ntrimmed=ntrimmed, overlap_len=overlap_len, no_trim=omit_trim,
        validate=True)

    # Run local alignment; handle the ncores/nthreads option for cutadapt versus bowtie2 options
    bowtie2_nthreads = 1 if nthreads == 0 else nthreads
    bta = baw(f1=fqp.trimmed_f1, ref=ref_fa, f2=fqp.trimmed_f2, outdir=outdir, outbam=None, local=True,
              nthreads=bowtie2_nthreads)

    # Run deduplication which may be done in at least two ways (standard and consensus)
    preproc_in_bam = bta.output_bam
    if consensus_dedup:
        # Run consensus deduplication (majority vote for each base call within a read's UMI network/group)
        rg = ReadGrouper(in_bam=bta.output_bam, outdir=outdir)
        cdp = ConsensusDeduplicatorPreprocessor(group_bam=rg.group_bam, outdir=outdir, nthreads=nthreads)
        cd = ConsensusDeduplicator(in_bam=cdp.preprocess_bam, ref=ref_fa, outdir=outdir, out_bam=None,
                                   nthreads=nthreads, contig_del_thresh=contig_del_thresh)
        cd.workflow()
        preproc_in_bam = cd.out_bam

    # Optionally run primer masking
    vc_in_bam = preproc_in_bam
    if primers is not None:

        # Make sure to pass the proper sort command based on the qname format
        if consensus_dedup:
            sort_cmd = QNAME_SORTS[INT_FORMAT_INDEX]

        rm = ReadMasker(
            in_bam=preproc_in_bam, feature_file=primers, race_like=race_like, sort_cmd=sort_cmd, outdir=outdir)
        rm.workflow()
        vc_in_bam = rm.out_bam

    # Initialize the VariantCaller and prepare the alignments
    vc = VariantCaller(
        am=vc_in_bam, targets=targets, ref=ref_fa, trx_gff=gff, gff_ref=gff_ref, primers=primers,
        output_dir=outdir, nthreads=nthreads, mut_sig=mut_sig)

    # Run variant calling
    output_vcf, output_bed = vc.workflow(min_bq, max_nm, min_supporting_qnames, max_mnp_window)

    return output_vcf, output_bed


def main():
    """Runs the workflow when called from command line."""

    parsed_args = parse_commandline_params(sys.argv[1:])
    args_dict = vars(parsed_args)

    if parsed_args.subcommand == SIM_WORKFLOW:

        _, _, _ = sim_workflow(
            bam=args_dict["alignments"], vcf=args_dict["vcf"], race_like=args_dict["race_like"],
            ensembl_id=args_dict["ensembl_id"], reference_dir=args_dict["reference_dir"],
            ref=args_dict["reference"], primers=args_dict["primers"], outdir=args_dict["outdir"],
            random_seed=args_dict["random_seed"], force_edit=args_dict["force_edit"],
            nthreads=args_dict["nthreads"])

    elif parsed_args.subcommand == CALL_WORKFLOW:

        _, _ = call_workflow(
            fastq1=args_dict["fastq1"], fastq2=args_dict["fastq2"],
            r1_fiveprime_adapters=args_dict["r1_fiveprime_adapters"],
            r1_threeprime_adapters=args_dict["r1_threeprime_adapters"], race_like=parsed_args["race_like"],
            ensembl_id=args_dict["ensembl_id"], reference_dir=args_dict["reference_dir"], ref=args_dict["reference"],
            transcript_gff=args_dict["transcript_gff"], gff_reference=args_dict["gff_reference"],
            targets=VariantCaller.VARIANT_CALL_TARGET,outdir=args_dict["outdir"], primers=args_dict["primers"],
            primer_fa=args_dict["primer_fasta"], primer_nm_allowance=args_dict["primer_nm_allowance"],
            consensus_dedup=args_dict["consensus_deduplicate"], umi_regex=args_dict["umi_regex"],
            contig_del_thresh=args_dict["contig_del_threshold"], min_bq=args_dict["min_bq"],
            max_nm=args_dict["max_nm"], min_supporting_qnames=args_dict["min_supporting"],
            max_mnp_window=args_dict["max_mnp_window"], nthreads=args_dict["nthreads"],
            ntrimmed=args_dict["ntrimmed"], overlap_len=parsed_args["overlap_length"],
            trim_bq=args_dict["trim_bq"], omit_trim=args_dict["omit_trim"],
            mut_sig=args_dict["mutagenesis_signature"])


if __name__ == "__main__":
    _logger.info("Started %s" % sys.argv[0])
    main()
    _logger.info("Completed %s" % sys.argv[0])
