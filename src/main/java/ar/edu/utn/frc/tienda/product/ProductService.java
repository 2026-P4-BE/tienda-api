package ar.edu.utn.frc.tienda.product;

import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class ProductService {

    private final ProductRepository repository;

    public ProductService(ProductRepository repository) {
        this.repository = repository;
    }

    public List<Product> findAll() {
        return repository.findAll();
    }

    public Product findById(Long id) {
        return repository.findById(id).orElseThrow(() -> new ProductNotFoundException(id));
    }

    public Product create(ProductRequest request) {
        return repository.save(new Product(request.name(), request.price(), request.stock()));
    }

    public Product update(Long id, ProductRequest request) {
        Product product = findById(id);
        product.setName(request.name());
        product.setPrice(request.price());
        product.setStock(request.stock());
        return repository.save(product);
    }

    public void delete(Long id) {
        repository.delete(findById(id));
    }
}
