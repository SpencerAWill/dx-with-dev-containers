using Azure.Storage.Blobs;
using Data;
using Microsoft.EntityFrameworkCore;

namespace WebApi.Endpoints;

public static class StatusEndpoints
{
    private record ServiceStatus(string Name, bool Healthy, string? Error = null);

    public static void MapStatusEndpoints(this WebApplication app)
    {
        app.MapGet("/api/status", async (
            AppDbContext db,
            BlobServiceClient blobService,
            IConfiguration config) =>
        {
            var checks = await Task.WhenAll(
                CheckSqlServer(db),
                CheckAzurite(blobService),
                CheckServiceBus(config),
                CheckModelRunner(config));

            return Results.Ok(new
            {
                healthy = checks.All(c => c.Healthy),
                services = checks
            });
        });
    }

    private static async Task<ServiceStatus> CheckSqlServer(AppDbContext db)
    {
        try
        {
            await db.Database.ExecuteSqlRawAsync("SELECT 1");
            return new ServiceStatus("SQL Server", true);
        }
        catch (Exception ex)
        {
            return new ServiceStatus("SQL Server", false, ex.Message);
        }
    }

    private static async Task<ServiceStatus> CheckAzurite(BlobServiceClient blobService)
    {
        try
        {
            await blobService.GetPropertiesAsync();
            return new ServiceStatus("Azurite (Blob Storage)", true);
        }
        catch (Exception ex)
        {
            return new ServiceStatus("Azurite (Blob Storage)", false, ex.Message);
        }
    }

    private static async Task<ServiceStatus> CheckServiceBus(IConfiguration config)
    {
        try
        {
            var connectionString = config.GetConnectionString("ServiceBus");
            if (string.IsNullOrEmpty(connectionString))
                return new ServiceStatus("Service Bus", false, "Connection string not configured");

            await using var client = new Azure.Messaging.ServiceBus.ServiceBusClient(connectionString);
            await using var sender = client.CreateSender("image-processing");
            // Creating a sender validates the connection
            return new ServiceStatus("Service Bus", true);
        }
        catch (Exception ex)
        {
            return new ServiceStatus("Service Bus", false, ex.Message);
        }
    }

    private static async Task<ServiceStatus> CheckModelRunner(IConfiguration config)
    {
        try
        {
            var endpoint = config["VisionModel:Endpoint"];
            if (string.IsNullOrEmpty(endpoint))
                return new ServiceStatus("Docker Model Runner", false, "Not configured");

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
            var response = await http.GetAsync($"{endpoint}/v1/models");
            response.EnsureSuccessStatusCode();
            return new ServiceStatus("Docker Model Runner", true);
        }
        catch (Exception ex)
        {
            return new ServiceStatus("Docker Model Runner", false, ex.Message);
        }
    }
}
