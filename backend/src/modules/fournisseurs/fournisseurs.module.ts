import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FournisseursController } from './fournisseurs.controller';
import { FournisseursService } from './fournisseurs.service';
import { Fournisseur } from './entities/fournisseur.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Fournisseur]),
  ],
  controllers: [FournisseursController],
  providers: [FournisseursService],
  exports: [TypeOrmModule],
})
export class FournisseursModule {}