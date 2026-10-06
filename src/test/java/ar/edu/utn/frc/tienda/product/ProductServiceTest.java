package ar.edu.utn.frc.tienda.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock
    private ProductRepository repository;

    @InjectMocks
    private ProductService service;

    private final ProductRequest request = new ProductRequest("Monitor", new BigDecimal("199.99"), 5);

    @Test
    void findAllReturnsEveryProduct() {
        when(repository.findAll()).thenReturn(List.of(new Product("A", BigDecimal.ONE, 1)));

        assertThat(service.findAll()).hasSize(1);
    }

    @Test
    void findByIdReturnsProduct() {
        Product product = new Product("A", BigDecimal.ONE, 1);
        when(repository.findById(1L)).thenReturn(Optional.of(product));

        assertThat(service.findById(1L)).isSameAs(product);
    }

    @Test
    void findByIdThrowsWhenMissing() {
        when(repository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.findById(99L))
                .isInstanceOf(ProductNotFoundException.class)
                .hasMessageContaining("99");
    }

    @Test
    void createSavesNewProduct() {
        when(repository.save(any(Product.class))).thenAnswer(invocation -> invocation.getArgument(0));

        Product created = service.create(request);

        assertThat(created.getName()).isEqualTo("Monitor");
        assertThat(created.getPrice()).isEqualByComparingTo("199.99");
        assertThat(created.getStock()).isEqualTo(5);
    }

    @Test
    void updateOverwritesFields() {
        Product existing = new Product("Old", BigDecimal.ONE, 1);
        when(repository.findById(1L)).thenReturn(Optional.of(existing));
        when(repository.save(existing)).thenReturn(existing);

        Product updated = service.update(1L, request);

        assertThat(updated.getName()).isEqualTo("Monitor");
        assertThat(updated.getStock()).isEqualTo(5);
    }

    @Test
    void deleteRemovesExistingProduct() {
        Product existing = new Product("A", BigDecimal.ONE, 1);
        when(repository.findById(1L)).thenReturn(Optional.of(existing));

        service.delete(1L);

        verify(repository).delete(existing);
    }
}
