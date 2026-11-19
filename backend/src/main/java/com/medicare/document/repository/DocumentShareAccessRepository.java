package com.medicare.document.repository;

import com.medicare.document.entity.DocumentShareAccess;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DocumentShareAccessRepository extends JpaRepository<DocumentShareAccess, Long> {
    List<DocumentShareAccess> findTop50ByShareIdOrderByAccessedAtDescIdDesc(Long shareId);
}
