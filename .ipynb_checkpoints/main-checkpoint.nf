
// Declare syntax version
nextflow.enable.dsl=2
// Script parameters
//params.GTF_GZ_LINK = 'http://ftp.ensembl.org/pub/release-106/gtf/homo_sapiens/Homo_sapiens.GRCh38.106.gtf.gz'
//params.TRANSCRIPTOME_REFERENCE = "human"
//params.KALLISTO_BIN = '/home/lf114/miniconda3/envs/perturbseq_pipeline/bin/kallisto'
//params.GENOME = 'https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz'
//params.GUIDE_FEATURES = '5p27sgRNA_guide_metainfo_modified.xlsx'
//params.CHEMISTRY = '0,0,16:0,16,26:0,26,0,1,0,0'
//params.THREADS = 15
//params.DISTANCE_NEIGHBORS = 1000000
//params.IN_TRANS = "FALSE"
//params.FASTQ_FILES_TRANSCRIPTS = ['5p27sgRNAGex_02KRWD_11408_S3_L001_R1_001.fastq.gz 5p27sgRNAGex_02KRWD_11408_S3_L001_R2_001.fastq.gz']
//params.FASTQ_NAMES_TRANSCRIPTS = ['S1_L1']
//params.FASTQ_FILES_GUIDES = ['5p27sgRNAsgRNA_02KRWK_11408_S15_L001_R1_001.fastq.gz 5p27sgRNAsgRNA_02KRWK_11408_S15_L001_R2_001.fastq.gz' ]
//params.FASTQ_NAMES_GUIDES = ['S1_L1']
//params.CREATE_REF = false




workflow {
   dir_images_composition_scrna =  compositionREADSscRNA(Channel.from(params.FASTQ_NAMES_TRANSCRIPTS), Channel.from(params.FASTQ_FILES_TRANSCRIPTS))
   dir_images_composition_guides = compositionREADSGuides(Channel.from(params.FASTQ_NAMES_GUIDES), Channel.from(params.FASTQ_FILES_GUIDES))

   gtf_out = downloadGTF(params.GTF_GZ_LINK)
   downloadReference(Channel.of(params.TRANSCRIPTOME_REFERENCE), Channel.of(params.KALLISTO_BIN) )
   downloadGenome (Channel.of(params.GENOME))
   guide_feature_preprocessed = guidePreprocessing(params.GUIDE_FEATURES)
   creatingGuideRef( downloadGenome.out.genome, Channel.of(params.KALLISTO_BIN), guide_feature_preprocessed.guide_features, params.CREATE_REF )
    
    
   map_rna = mappingscRNA (
                 Channel.from(params.FASTQ_NAMES_TRANSCRIPTS),
                 Channel.from(params.FASTQ_FILES_TRANSCRIPTS),
                 downloadReference.out.transcriptome_idx.collect(),
                 downloadReference.out.t2t_transcriptome_index.collect(),
                 Channel.of(params.KALLISTO_BIN).collect(),
                 Channel.of(params.CHEMISTRY).collect(),
                 Channel.of(params.THREADS).collect(),

                )
    
   map_guide = mappingGuide (
                 Channel.from(params.FASTQ_NAMES_GUIDES),
                 Channel.from(params.FASTQ_FILES_GUIDES), 
                 creatingGuideRef.out.guide_index.collect(),
                 creatingGuideRef.out.t2tguide_index.collect(),
                 Channel.of(params.KALLISTO_BIN).collect(),
                 Channel.of(params.CHEMISTRY).collect(),
                 Channel.of(params.THREADS).collect())
    
    
    dir_count_files = map_guide.ks_guide_out.join(map_rna.ks_transcripts_out, remainder: true).flatten().toList().view()
    dir_count_files.view()
    df_initialized = preprocessing(dir_count_files)
    out_processed = filtering(df_initialized.df_initial_files, dir_count_files )
    out_processed.guide_ann.view()
    out_processed.transcripts_ann.view()
    pert_loader_out = PerturbLoaderGeneration(out_processed.guide_ann, out_processed.transcripts_ann , gtf_out.gtf , params.DISTANCE_NEIGHBORS, params.IN_TRANS )
    runSceptre(pert_loader_out.perturb_piclke)
    
    
}


process downloadGTF {
    input:
    val gtf_gz_path
    output:
    path "transcripts.gtf" , emit: gtf
    script:
    """    
    wget -O - $gtf_gz_path | gunzip -c > transcripts.gtf
    """
}



process downloadReference {
    input:
    val ref_name 
    path k_bin 
    
    output:
    path "transcriptome_index.idx" , emit: transcriptome_idx
    path "transcriptome_t2g.txt"   , emit: t2t_transcriptome_index

    script:
    """
        kb ref -d $ref_name -i transcriptome_index.idx -g transcriptome_t2g.txt --kallisto ${k_bin}
    """
}

process downloadGenome {
    input:
    val genome_path
    output:
    path "genome.fa.gz" , emit: genome
    script:
    """
        wget $genome_path -O genome.fa.gz 
    """


}


process guidePreprocessing {
    cache 'lenient'
    debug true
    input:
    path (guide_input_table)
    output:
    path "guide_features.txt" , emit: guide_features
    script:
    """    
    guide_table_processing.py  $guide_input_table
    """
}





process creatingGuideRef {
    cache 'lenient'
    input:
    val genome_path
    path k_bin
    path guide_features
    val create_ref
    output:
    path "guide_index.idx" ,  emit: guide_index
    path "t2guide.txt" , emit: t2tguide_index
    script:
    
    """
        kb ref -i guide_index.idx -f1 $genome_path -g t2guide.txt --kallisto $k_bin  --workflow kite $guide_features 

    """


    
}

process compositionREADSscRNA {
    debug true
    input:
    tuple val(out_name_dir)
    tuple val(string_fastqz)
    output:
    path ("transcript_${out_name_dir}_composition"),  emit: composition_plot_dir

    script:
    
        """
        mkdir transcript_"${out_name_dir}_composition"
        fq_composition.py $string_fastqz transcript_${out_name_dir}                                                                
        """
} 


process compositionREADSGuides {
    debug true
    input:
    tuple val(out_name_dir)
    tuple val(string_fastqz)
    output:
    path ("guide_${out_name_dir}_composition"),  emit: composition_plot_dir

    script:
    
        """
        mkdir "guide_${out_name_dir}_composition"
        fq_composition.py $string_fastqz guide_${out_name_dir}                                                                
        """
} 






process mappingscRNA {
    debug true
    input:
    tuple val(out_name_dir)
    tuple val(string_fastqz)
    tuple path(transcriptome_idx)
    tuple path(t2t_transcriptome_index)
    tuple path(k_bin)
    tuple val(chemistry)
    tuple val(threads)
    output:
    path ("${out_name_dir}_ks_transcripts_out"),  emit: ks_transcripts_out

    script:
    
        """
        kb count -i $transcriptome_idx -g  $t2t_transcriptome_index --verbose --workflow kite --h5ad --kallisto $k_bin -x $chemistry -o ${out_name_dir}_ks_transcripts_out -t $threads $string_fastqz  --overwrite                                                                   
        """
} 

process mappingGuide {
    debug true
    input:
    tuple val(out_name_dir)
    tuple val(string_fastqz)
    tuple (path guide_index)
    tuple (path t2tguide_index)
    tuple path(k_bin)
    tuple val(chemistry)
    tuple val(threads)
    output:
    path ("${out_name_dir}_ks_guide_out"),  emit: ks_guide_out
    script:
        """
        kb count -i $guide_index       -g  $t2tguide_index --verbose   --report  --workflow kite --h5ad --kallisto $k_bin -x $chemistry  -o ${out_name_dir}_ks_guide_out -t $threads $string_fastqz --overwrite
        """
} 

 


process capture_variables_and_save_list{
    debug true
    input:
    val received
    val out_name
    output:
    path "${out_name}.txt",  emit: out_file
    script:
    """
    echo  '${received}' > ${out_name}.txt 
    """
}








process preprocessing {
    debug true
    input:
    path (count_list)
    output:
    path 'initial_preprocessing_file_names.txt', emit: df_initial_files
    script:
    """    
    preprocessing.py  ${count_list} 

    """   
    
}


process filtering{
    debug true
    input:
    path (path_df)
    path (all_files)
    output:
    path 'results_per_lane/processed_anndata_guides_data.h5ad', emit: guide_ann
    path 'results_per_lane/processed_anndata_transcripts_data.h5ad',  emit: transcripts_ann
    script:
    """
    #use -merge to merge the guides
    # I need to add these parameters to the pipeline config  mito...cellnumber...merge...guide_limit
    filtering_and_lane_merging.py --path ${path_df} --expected_cell_number 8000 --mito_specie hsapiens --mito_expected_percentage 0.2 --percentage_of_cells_to_include_transcript 0.2  --guide_umi_limit 5

    """
}



IN_GUIDE = args.in_guide
IN_EXP = args.in_exp
GTF_IN = args.gtf_in
IN_TRANS = args.in_trans
DISTANCE_FROM_GUIDE = args.distance_from_guide

process PerturbLoaderGeneration {
    debug true
    input:
    path (in_guide)
    path (in_exp)
    path (gtf_in)
    val (distance_from_guide)
    val (in_trans)
    output:
    path 'perturbdata.pkl', emit: perturb_piclke
    
   """ 
   PerturbLoader_generation.py --in_guide $in_guide --in_exp $in_exp --gtf_in $gtf_in  --distance_from_guide $distance_from_guide --in_trans $in_trans

    """   
}


process runSceptre {
    debug true
    input:
    path (perturbloader_pickle)

    
   """ 
   runSceptre.py $perturbloader_pickle

    """   
}





