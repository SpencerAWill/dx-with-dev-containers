using Azure.Messaging.ServiceBus;
using Azure.Storage.Blobs;
using Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Integration.Tests;

public class ApiFixture : WebApplicationFactory<Program>, IAsyncLifetime
{
    private const string TestConnectionString =
        "Server=app-mssql;Database=SnapSort_Test;User Id=sa;Password=App_Passw0rd!;TrustServerCertificate=true";

    private const string AzuriteConnectionString =
        "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;";

    private const string ServiceBusConnectionString =
        "Endpoint=sb://servicebus-emulator;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace DbContext with test database
            var dbDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            if (dbDescriptor is not null)
                services.Remove(dbDescriptor);

            services.AddDbContext<AppDbContext>(options =>
                options.UseSqlServer(TestConnectionString));

            // Replace BlobServiceClient with real Azurite
            var blobDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(BlobServiceClient));
            if (blobDescriptor is not null)
                services.Remove(blobDescriptor);

            services.AddSingleton(_ => new BlobServiceClient(AzuriteConnectionString));

            // Replace ServiceBusClient with real emulator
            var sbDescriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(ServiceBusClient));
            if (sbDescriptor is not null)
                services.Remove(sbDescriptor);

            services.AddSingleton(_ => new ServiceBusClient(ServiceBusConnectionString));
        });
    }

    public async Task InitializeAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    public new async Task DisposeAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureDeletedAsync();
        await base.DisposeAsync();
    }
}
