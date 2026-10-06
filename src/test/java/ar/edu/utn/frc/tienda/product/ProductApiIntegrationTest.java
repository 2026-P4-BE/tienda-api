package ar.edu.utn.frc.tienda.product;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class ProductApiIntegrationTest {

    private static final String BODY = "{\"name\": \"Headset\", \"price\": 59.90, \"stock\": 10}";

    @Autowired
    private MockMvc mockMvc;

    @Test
    void listReturnsSeedData() throws Exception {
        mockMvc.perform(get("/api/products"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(greaterThanOrEqualTo(2))));
    }

    @Test
    void createThenGetUpdateAndDelete() throws Exception {
        String created = mockMvc.perform(post("/api/products")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(BODY))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("Headset"))
                .andReturn().getResponse().getContentAsString();
        String id = created.replaceAll(".*\"id\":(\\d+).*", "$1");

        mockMvc.perform(get("/api/products/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stock").value(10));

        mockMvc.perform(put("/api/products/" + id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\": \"Headset Pro\", \"price\": 89.90, \"stock\": 3}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Headset Pro"));

        mockMvc.perform(delete("/api/products/" + id))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/products/" + id))
                .andExpect(status().isNotFound());
    }

    @Test
    void createRejectsInvalidPayload() throws Exception {
        mockMvc.perform(post("/api/products")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\": \"\", \"price\": -1, \"stock\": -5}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void healthIsUp() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }

    @Test
    void versionMatchesPom() throws Exception {
        mockMvc.perform(get("/api/version"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value("1.0.0"));
    }
}
