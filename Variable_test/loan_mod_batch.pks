CREATE OR REPLACE PACKAGE loan_mod_batch_pkg AS
    -- Constants
    c_batch_size CONSTANT NUMBER := 1000;
    c_max_retries CONSTANT NUMBER := 3;
    
    -- Types
    TYPE t_loan_id_table IS TABLE OF VARCHAR2(20);
    
    -- Core procedures
    PROCEDURE process_modification_batch(
        p_batch_id IN NUMBER,
        p_processing_date IN DATE DEFAULT SYSDATE
    );
    
END loan_mod_batch_pkg;
/