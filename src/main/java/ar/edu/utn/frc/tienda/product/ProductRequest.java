package ar.edu.utn.frc.tienda.product;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

public record ProductRequest(
        @NotBlank String name,
        @NotNull @DecimalMin("0.0") BigDecimal price,
        @Min(0) int stock) {
}
