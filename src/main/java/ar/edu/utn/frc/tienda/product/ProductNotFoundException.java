package ar.edu.utn.frc.tienda.product;

public class ProductNotFoundException extends RuntimeException {

    public ProductNotFoundException(Long id) {
        super("Product " + id + " not found");
    }
}
