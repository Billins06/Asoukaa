import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { FournisseursController } from './fournisseurs.controller';
import { FournisseursService }    from './fournisseurs.service';
import { Fournisseur }            from './entities/fournisseur.entity';
import { CommonModule }           from '../../common/common.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Fournisseur]),
    CommonModule,
  ],
  controllers: [FournisseursController],
  providers:   [FournisseursService],
  exports:     [FournisseursService, TypeOrmModule],
})
export class FournisseursModule {}  