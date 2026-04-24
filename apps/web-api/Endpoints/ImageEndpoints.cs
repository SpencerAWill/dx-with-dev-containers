using Data;
using Microsoft.EntityFrameworkCore;

namespace WebApi.Endpoints;

public static class ImageEndpoints
{
    public static void MapImageEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/images");

        group.MapGet("/", async (AppDbContext db) =>
        {
            var images = await db.Images
                .OrderByDescending(i => i.UploadedAt)
                .ToListAsync();
            return Results.Ok(images);
        });

        group.MapGet("/{id:guid}", async (Guid id, AppDbContext db) =>
        {
            var image = await db.Images.FindAsync(id);
            return image is not null ? Results.Ok(image) : Results.NotFound();
        });
    }
}
