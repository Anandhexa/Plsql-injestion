CREATE OR REPLACE PACKAGE BODY loan_mod_batch_pkg AS
    
    
    PROCEDURE process_modification_batch(
        p_batch_id IN NUMBER,
        p_processing_date IN DATE DEFAULT SYSDATE
    ) IS
        v_loans t_loan_id_table;
        v_processed_count NUMBER := 0;
        v_failed_count NUMBER := 0;
        v_start_time TIMESTAMP;
    BEGIN
        v_start_time := SYSTIMESTAMP;
        
        -- Log batch start
        log_batch_progress(
            p_batch_id,
            'STARTED',
            'Starting modification batch processing'
        );
        
        -- Get loans pending modification
        SELECT loan_id
        BULK COLLECT INTO v_loans
        FROM loan_modification_history
        WHERE batch_id = p_batch_id
        AND status = 'PENDING'
        AND effective_date <= p_processing_date;
        
        -- Process modifications in batches
        FOR i IN 0 .. TRUNC((v_loans.COUNT - 1) / c_batch_size) LOOP
            BEGIN
                FORALL j IN (i * c_batch_size + 1) .. 
                           LEAST((i + 1) * c_batch_size, v_loans.COUNT)
                    UPDATE loan_modification_history
                    SET status = 'ACTIVE',
                        last_updated_date = SYSDATE,
                        last_updated_by = USER
                    WHERE loan_id = v_loans(j)
                    AND batch_id = p_batch_id
                    AND status = 'PENDING';
                
                v_processed_count := v_processed_count + SQL%ROWCOUNT;
                
                -- Update loan master status
                FORALL j IN (i * c_batch_size + 1) .. 
                           LEAST((i + 1) * c_batch_size, v_loans.COUNT)
                    UPDATE loan_master
                    SET modification_flag = 'Y',
                        modified_date = SYSDATE
                    WHERE loan_id = v_loans(j);
                
                COMMIT;
                
            EXCEPTION
                WHEN OTHERS THEN
                    ROLLBACK;
                    v_failed_count := v_failed_count + 1;
                    
                    -- Log error
                    investor_reporting_pkg.log_exception(
                        NULL,
                        v_loans(i * c_batch_size + 1),
                        'BATCH_MOD_ERROR',
                        'HIGH',
                        'Error processing modification batch: ' || SQLERRM
                    );
            END;
        END LOOP;
        
        -- Log batch completion
        log_batch_progress(
            p_batch_id,
            'COMPLETED',
            'Processed ' || v_processed_count || ' modifications, ' ||
            v_failed_count || ' failures. ' ||
            'Duration: ' || 
            EXTRACT(MINUTE FROM (SYSTIMESTAMP - v_start_time)) || ' minutes'
        );
        
        -- Handle failed modifications if any
        IF v_failed_count > 0 THEN
            handle_failed_modifications(p_batch_id);
        END IF;
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            log_batch_progress(
                p_batch_id,
                'FAILED',
                'Batch processing failed: ' || SQLERRM
            );
            RAISE;
    END process_modification_batch;
    
END loan_mod_batch_pkg;
/ 